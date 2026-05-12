# Changelog

All notable changes to this Cowork port of [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) are documented here. This is a port — upstream's own changelog is the source of truth for snapshot-logic and skill-spec changes.

## [0.1.0] — 2026-05-12

First release. Packages Christopher Chadwick's [claude-code-handoff](https://github.com/Sting25/claude-code-handoff) as a Claude Code plugin installable through the Cowork desktop app's plugin UI.

### Added (new in this port)

- `.claude-plugin/marketplace.json` — single-plugin marketplace manifest so the repo can be added directly via Customize → Add marketplace in the Cowork app.
- `cowork-plugin/.claude-plugin/plugin.json` — plugin manifest with full upstream attribution in the description prose.
- `cowork-plugin/hooks/hooks.json` — declarative `SessionStart` / `SessionEnd` / `Stop` wiring (`${CLAUDE_PLUGIN_ROOT}/bin/...`). Replaces the upstream `install.sh` settings.json patcher; no `jq` needed at install time.
- `cowork-plugin/bin/handoff_turn_format.pl` — Perl `JSON::PP` helper that replaces the upstream `jq`-based transcript parser. MSYS Git Bash on Windows ships without `jq`; Perl is present on every Claude Code surface (MSYS, macOS, Ubuntu in the Cowork VM).
- `mkdir`-based atomic lock in `handoff_turn_append.sh`, replacing upstream's `flock` (also missing on MSYS Git Bash).
- Three-tier fallback chain in `handoff_turn_append.sh` for resolving `session_id` and `transcript_path`:
  1. JSON stdin payload (interactive Claude Code, the upstream contract).
  2. `CLAUDE_ENV_FILE` path-parse (SessionStart-derived contexts).
  3. `CLAUDE_PROJECT_DIR` → encoded `~/.claude/projects/<encoded>/<sid>.jsonl` filesystem lookup (headless mode, and any future hook event that doesn't expose session info directly).
- Headless mode support: hooks now produce both `handoff_current.md` and `handoff_raw_<sid>.md` when fired by `claude -p`. The upstream contract was stdin-only, which doesn't work in headless mode.
- `CLAUDE_PROJECT_DIR`-preferred repo resolution in both scripts (was `git rev-parse` from pwd). Necessary because the Cowork app's Code-tab sessions root the shell at `C:\Users\scott\.klodock`, not the user's project. Falls back to pwd only when `CLAUDE_PROJECT_DIR` is unset.
- `cowork-plugin/bin/probe_hook.sh` — diagnostic env-logger wired ahead of each real hook. Writes to `~/handoff_probe.log` with cwd, env, git topology, and stdin size. Used to debug load failures.
- `LICENSE` — upstream MIT preserved verbatim, copyright (c) 2026 Christopher Chadwick. (Required by MIT; included as a deliberate first-class artifact.)
- [`CREDITS.md`](CREDITS.md) — per-file attribution of what's upstream vs what's port-specific.
- [`VERIFICATION.md`](docs/VERIFICATION.md) — full receipts from headless end-to-end testing on Windows MSYS Git Bash, including probe-log captures, both artifacts produced, and the exact commits that landed each fix.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — hook lifecycle, data flow, and the cwd-resolution decision tree.
- [`USER-MANUAL.md`](USER-MANUAL.md) — install, configuration env vars, triggers, troubleshooting.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — what changes go upstream vs here.

### Same as upstream (unchanged or near-unchanged)

- `bin/write_handoff.sh` snapshot logic, configuration env vars, substrate pattern. Only the inline doc-string and the repo-root resolution were edited.
- `bin/handoff_turn_append.sh` cursor-based deduplication, three-newest pruning, noise-tag stripping. Locking semantics preserved (mkdir-lock has the same atomicity guarantees as flock).
- `skills/handoff/SKILL.md` triggers, `Notes from this session` workflow, banner format, "Raw dump fallback" section. Adapted only where it referenced absolute `~/.claude/bin/...` paths (now `${CLAUDE_PLUGIN_ROOT}/bin/...`) and to add a Cowork-VM-tab caveat.
- `.claude/handoff_current.md` and `.claude/handoff_backups/handoff_raw_<session_id>.md` output shapes.
- `HANDOFF_*` environment variable interface (`HANDOFF_INFLIGHT_DIRS`, `HANDOFF_SUBSTRATE_NAME`, `HANDOFF_SUBSTRATE_INFLIGHT_DIRS`, `HANDOFF_NO_GITIGNORE_BOOTSTRAP`).

### Verified

- `claude plugin validate` passes on both `cowork-plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
- `claude plugin list` reports `✔ enabled` after `claude plugin enable claude-code-handoff@claude-code-handoff-cowork`.
- Real `claude -p` headless run against a git repo on Windows MSYS Git Bash with `ANTHROPIC_API_KEY`:
  - All three hooks fired (`SessionStart`, `Stop`, `SessionEnd` — see [`docs/VERIFICATION.md`](docs/VERIFICATION.md) for probe-log captures).
  - `<repo>/.claude/handoff_current.md` written (1370 bytes, valid markdown, git state intact).
  - `<repo>/.claude/handoff_backups/handoff_raw_<UUID>.md` written (23 lines, real `User:` / `Assistant:` blocks from the actual conversation).
- `bash -n` + `perl -c` clean on all scripts. JSON manifests valid via `decode_json`.

### Known limitations

- **Cowork-VM tab hooks don't fire.** Documented in [anthropics/claude-code#27398](https://github.com/anthropics/claude-code/issues/27398) and [#40495](https://github.com/anthropics/claude-code/issues/40495). Not a port issue — the in-VM CLI is spawned with `--setting-sources user` which excludes plugin-scoped hooks. The `/handoff` skill itself loads fine in the Cowork-VM tab; use it manually there.
- **Chat tab has no shell.** No plugin behavior in the Chat tab. Skill won't even appear.
- **Final Cowork-app interactive verification not on file.** Headless `claude -p` testing on this machine proves the plugin's logic works against the same binary the Cowork app spawns. The probe (`bin/probe_hook.sh`) is deployed; the first Cowork-app Code-tab session run after install will write to `~/handoff_probe.log` with full hook-context env. If anything misbehaves, that log answers it.
