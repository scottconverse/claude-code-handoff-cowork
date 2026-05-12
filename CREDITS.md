# Credits

## Upstream author

**Christopher Chadwick** ([@Sting25](https://github.com/Sting25))

Author of the upstream project: [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff).

All of the load-bearing logic in this repo is his work, used here under the MIT license preserved verbatim in [`LICENSE`](LICENSE):

- The snapshot script (`bin/write_handoff.sh`) — captures HEAD, branch, recent commits, working tree, and in-flight `.md` docs to `<repo>/.claude/handoff_current.md`. This port edits only the inline doc-string; the snapshot logic, configuration env vars, and substrate pattern are unchanged.
- The Stop-hook transcript appender (`bin/handoff_turn_append.sh`). This port replaces `flock` with `mkdir`-based locking and the `jq` pipeline with a Perl `JSON::PP` helper, but the locking semantics, cursor-based deduplication, and turn-block format are upstream's design.
- The `/handoff` skill spec (`skills/handoff/SKILL.md`) — triggers, "Notes from this session" workflow, banner format, "Raw dump fallback" section. This port adjusts script paths from `~/.claude/bin/...` to `${CLAUDE_PLUGIN_ROOT}/bin/...` and adds a paragraph about the Cowork-VM-tab hook caveat.
- The output shape of `.claude/handoff_current.md` and `.claude/handoff_backups/handoff_raw_<session_id>.md`.
- The `HANDOFF_*` environment variable interface.

## This port

**Scott Converse** ([@scottconverse](https://github.com/scottconverse))

Added Cowork-installable packaging:
- `.claude-plugin/marketplace.json` (single-plugin marketplace manifest).
- `cowork-plugin/.claude-plugin/plugin.json` (plugin manifest).
- `cowork-plugin/hooks/hooks.json` (declarative `SessionStart` / `SessionEnd` / `Stop` wiring).
- `cowork-plugin/bin/handoff_turn_format.pl` (Perl `JSON::PP` helper that replaces the upstream `jq` pipeline, since `jq` is missing on MSYS Git Bash on Windows).
- `mkdir`-based atomic lock in `bin/handoff_turn_append.sh` (replaces `flock`, which is also missing on MSYS).
- Tab-by-tab support matrix documented in `cowork-plugin/README.md`, accounting for [anthropics/claude-code#27398](https://github.com/anthropics/claude-code/issues/27398) and [#40495](https://github.com/anthropics/claude-code/issues/40495).

## License

[MIT](LICENSE) — copyright (c) 2026 Christopher Chadwick, preserved verbatim from upstream. The port additions are under the same license.
