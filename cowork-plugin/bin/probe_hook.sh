#!/usr/bin/env bash
# probe_hook.sh — diagnostic logger for the three plugin hooks.
# Each hook calls this first with its event name, then does its real work.
# Output goes to ~/handoff_probe.log (never overwritten — appended).
#
# We want to know:
#   1. Did the hook fire at all? (presence of any line for that event)
#   2. What does the hook see for cwd, CLAUDE_PROJECT_DIR, CLAUDE_PLUGIN_ROOT?
#   3. Is the cwd a git worktree?

event="${1:-?}"
log="$HOME/handoff_probe.log"
ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

{
  printf '[%s] event=%s\n' "$ts" "$event"
  printf '  pwd=%s\n' "$(pwd 2>&1)"
  printf '  CLAUDE_PROJECT_DIR=%s\n' "${CLAUDE_PROJECT_DIR:-<empty>}"
  printf '  CLAUDE_PLUGIN_ROOT=%s\n' "${CLAUDE_PLUGIN_ROOT:-<empty>}"
  printf '  CLAUDE_CODE_ENTRYPOINT=%s\n' "${CLAUDE_CODE_ENTRYPOINT:-<empty>}"
  printf '  CLAUDE_CODE_IS_COWORK=%s\n' "${CLAUDE_CODE_IS_COWORK:-<empty>}"
  printf '  HOME=%s\n' "${HOME:-<empty>}"
  printf '  git_top_from_pwd=%s\n' "$(git rev-parse --show-toplevel 2>&1)"
  printf '  git_top_from_project_dir=%s\n' "$(git -C "${CLAUDE_PROJECT_DIR:-/nonexistent}" rev-parse --show-toplevel 2>&1)"
  if [ "$event" = "Stop" ] || [ "$event" = "SessionEnd" ]; then
    # Capture stdin payload too (hook events Stop/SessionEnd get JSON on stdin).
    payload="$(cat 2>/dev/null || true)"
    printf '  stdin_bytes=%d\n' "${#payload}"
    # Don't dump full payload (transcripts can be huge); show first 200 chars.
    if [ -n "$payload" ]; then
      printf '  stdin_head=%s\n' "$(printf '%s' "$payload" | head -c 200)"
    fi
  fi
  printf '\n'
} >> "$log" 2>&1

exit 0
