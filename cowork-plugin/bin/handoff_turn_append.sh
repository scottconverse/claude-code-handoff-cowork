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

# --- Read hook payload from stdin and extract session_id, transcript_path ---
payload="$(cat)"
parsed="$(printf '%s' "$payload" | perl -MJSON::PP -e '
  local $/; my $j = <STDIN>;
  my $o = eval { decode_json($j) } || {};
  print +($o->{session_id} // ""), "\n", +($o->{transcript_path} // ""), "\n";
')"
session_id="$(printf '%s' "$parsed"      | sed -n '1p')"
transcript_path="$(printf '%s' "$parsed" | sed -n '2p')"

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
