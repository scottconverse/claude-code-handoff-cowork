#!/usr/bin/env bash
# handoff_turn_append.sh — Stop hook companion to /handoff (Cowork-plugin port).
#
# Fires after every assistant turn. Reads the new lines that landed in the
# Claude Code transcript JSONL since the previous Stop, formats them into a
# human-readable turn block, and appends to:
#
#   <repo>/.claude/handoff_backups/handoff_raw_<session_id>.md
#
# Differences from the upstream CLI version:
#   - flock replaced with mkdir-based atomic lock (MSYS Git Bash on Windows
#     has no flock; mkdir is atomic everywhere).
#   - jq replaced with a bundled Perl helper (handoff_turn_format.pl), which
#     uses only JSON::PP (Perl core since 5.14, no CPAN install required).
#     Probe established jq is missing on Scott's MSYS install.
#
# Guards against duplication:
#   - A per-session mkdir lockdir serializes concurrent Stop hook fires.
#   - A cursor file tracks how many transcript lines we've already processed.
#   - System-reminder / command-* noise tags are stripped in the perl helper.
#
# Keeps only the 3 newest handoff_raw_*.md files in the backup dir.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
formatter="$script_dir/handoff_turn_format.pl"

# --- Resolve session_id and transcript_path.
# Primary source: JSON payload on stdin (interactive Claude Code passes
# {"session_id":..., "transcript_path":...}). In `claude -p` headless mode
# stdin is empty, so we fall back to deriving both from env vars:
#   - session_id from $CLAUDE_ENV_FILE (path includes the session UUID)
#   - transcript_path by searching $HOME/.claude/projects/*/<session_id>.jsonl
session_id=""
transcript_path=""

payload="$(cat 2>/dev/null || true)"
if [[ -n "$payload" ]]; then
  parsed="$(printf '%s' "$payload" | perl -MJSON::PP -e '
    local $/; my $j = <STDIN>;
    my $o = eval { decode_json($j) } || {};
    print +($o->{session_id} // ""), "\n", +($o->{transcript_path} // ""), "\n";
  ' 2>/dev/null)"
  session_id="$(printf '%s' "$parsed"      | sed -n '1p')"
  transcript_path="$(printf '%s' "$parsed" | sed -n '2p')"
fi

if [[ -z "$session_id" && -n "${CLAUDE_ENV_FILE:-}" ]]; then
  # CLAUDE_ENV_FILE is set during SessionStart and looks like
  # .../session-env/<UUID>/sessionstart-hook-0.sh
  candidate="$(basename "$(dirname "$CLAUDE_ENV_FILE")")"
  if [[ "$candidate" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    session_id="$candidate"
  fi
fi

# Last-resort fallback for headless mode (and any hook event that doesn't
# expose CLAUDE_ENV_FILE): find the newest .jsonl in the encoded project dir
# under ~/.claude/projects/. Claude Code encodes the project path by replacing
# `:`, `/`, and `\` with `-` (so C:\Users\foo becomes C--Users-foo).
if [[ -z "$transcript_path" && -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  winpath="$(cygpath -w "$CLAUDE_PROJECT_DIR" 2>/dev/null || printf '%s' "$CLAUDE_PROJECT_DIR")"
  encoded="$(printf '%s' "$winpath" | sed 's/[\\:/]/-/g')"
  project_jsonl_dir="$HOME/.claude/projects/$encoded"
  if [[ -d "$project_jsonl_dir" ]]; then
    transcript_candidate="$(ls -t "$project_jsonl_dir"/*.jsonl 2>/dev/null | head -1)"
    if [[ -n "$transcript_candidate" && -f "$transcript_candidate" ]]; then
      transcript_path="$transcript_candidate"
      [[ -z "$session_id" ]] && session_id="$(basename "$transcript_candidate" .jsonl)"
    fi
  fi
fi

if [[ -z "$transcript_path" && -n "$session_id" ]]; then
  transcript_path="$(find "$HOME/.claude/projects" -name "${session_id}.jsonl" -type f 2>/dev/null | head -1)"
fi

[[ -z "$session_id"        ]] && exit 0
[[ -z "$transcript_path"   ]] && exit 0
[[ ! -f "$transcript_path" ]] && exit 0

# --- Repo scope: only run inside git worktrees.
# Prefer CLAUDE_PROJECT_DIR (set by Claude Code to the launch cwd) over the
# shell's own cwd, because Cowork-app Code-tab sessions root the shell at
# .klodock (a Cowork sandbox dir), not the user's project.
repo_root=""
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  repo_root="$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [[ -z "$repo_root" ]]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
[[ -z "$repo_root" ]] && exit 0

backup_dir="$repo_root/.claude/handoff_backups"
mkdir -p "$backup_dir"

dump_file="$backup_dir/handoff_raw_${session_id}.md"
cursor_file="$backup_dir/.handoff_raw_${session_id}.cursor"
lock_dir="$backup_dir/.handoff_raw_${session_id}.lock.d"

# --- Serialize concurrent invocations via atomic mkdir.
#     If another instance is already running, exit clean — it'll pick up our turn.
if ! mkdir "$lock_dir" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT

# --- Cursor: how many transcript lines we've already processed ---
prev_count=0
if [[ -f "$cursor_file" ]]; then
  prev_count="$(cat "$cursor_file" 2>/dev/null || echo 0)"
  [[ "$prev_count" =~ ^[0-9]+$ ]] || prev_count=0
fi
curr_count="$(wc -l < "$transcript_path" | tr -d ' ')"

# Transcript shorter than cursor -> rotated/reset; skip this turn.
if (( curr_count < prev_count )); then
  exit 0
fi
if (( curr_count == prev_count )); then
  exit 0
fi

# --- Initialize dump file on first append ---
if [[ ! -f "$dump_file" ]]; then
  {
    printf '# Raw session dump\n\n'
    printf '**Session ID:** `%s`\n' "$session_id"
    printf '**Started:** %s\n\n' "$(date -u +'%Y-%m-%d %H:%M UTC')"
    printf '_Auto-appended turn-by-turn by the Stop hook (`handoff_turn_append.sh`).\n'
    printf 'Each block below is one user message + the assistant response that\n'
    printf 'followed. Tool outputs are truncated to keep the file readable; the\n'
    printf 'full transcript lives at `%s`. Recurring system-reminder /\n' "$transcript_path"
    printf 'command-* noise has been stripped._\n\n'
    printf -- '---\n'
  } > "$dump_file"
fi

# --- Append new turn block via perl helper ---
{
  printf '\n## Turn at %s\n\n' "$(date -u +'%Y-%m-%d %H:%M:%S UTC')"
  perl "$formatter" "$transcript_path" "$((prev_count + 1))" "$curr_count" || true
} >> "$dump_file"

# --- Update cursor atomically (tmp + mv) ---
tmp_cursor="$(mktemp "${cursor_file}.XXXXXX")"
echo "$curr_count" > "$tmp_cursor"
mv -f "$tmp_cursor" "$cursor_file"

# --- Prune to 3 newest dump files (and their cursor/lock files) ---
mapfile -t to_delete < <(
  ls -t "$backup_dir"/handoff_raw_*.md 2>/dev/null | tail -n +4
)
for old in "${to_delete[@]:-}"; do
  [[ -z "$old" ]] && continue
  rm -f -- "$old"
  base="$(basename "$old" .md)"
  id="${base#handoff_raw_}"
  rm -f  -- "$backup_dir/.handoff_raw_${id}.cursor"
  rm -rf -- "$backup_dir/.handoff_raw_${id}.lock.d"
done

exit 0
