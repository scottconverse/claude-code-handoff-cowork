# claude-code-handoff-cowork

A Cowork-installable port of **[Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff)** by Christopher Chadwick.

The upstream project solves "next session starts blind after context fills up." It snapshots the current repo's state on session exit (`<repo>/.claude/handoff_current.md`) and auto-loads that snapshot on the next session start, plus a `/handoff` slash command for manual invocation at clean boundaries. All of that mechanism — the snapshot script, the Stop-hook transcript appender, the `/handoff` skill spec — is Christopher Chadwick's work, used here under MIT.

This repo packages that work as a **plugin installable through the Claude Cowork desktop app**, and adapts it so it runs cleanly on the surfaces Cowork uses.

## What's the same as upstream

- `bin/write_handoff.sh` — the snapshot script. Functionally unchanged; only the inline doc-string was edited to reference the plugin install context rather than `~/.claude/bin/...` paths.
- `skills/handoff/SKILL.md` — the `/handoff` slash command spec. Adapted only where it references absolute `~/.claude/bin/...` paths; rewritten to use `${CLAUDE_PLUGIN_ROOT}/bin/...`. The trigger logic, banner, and `Raw dump fallback` section are upstream's.
- The `.claude/handoff_current.md` and `.claude/handoff_backups/handoff_raw_<session_id>.md` output shapes.
- The `HANDOFF_*` environment variables (substrate pattern, in-flight dirs, gitignore bootstrap).
- MIT license, copyright held by Christopher Chadwick. Preserved verbatim in this repo's [`LICENSE`](LICENSE).

## What's new in this port

- **Plugin manifest** (`cowork-plugin/.claude-plugin/plugin.json`) and **marketplace manifest** (`.claude-plugin/marketplace.json`) so the repo can be installed as a single-plugin marketplace via the Cowork app's plugin UI.
- **`cowork-plugin/hooks/hooks.json`** wires `SessionStart` / `SessionEnd` / `Stop` declaratively, replacing upstream's `install.sh` settings.json-patching approach.
- **`flock` replaced with `mkdir`-based atomic lock** in `handoff_turn_append.sh`. MSYS Git Bash on Windows has no `flock`; the upstream Stop-hook lock silently fails there. `mkdir` is atomic on every platform Claude Code targets.
- **`jq` replaced with `bin/handoff_turn_format.pl`**, a Perl helper using only `JSON::PP` (Perl core module, no CPAN install needed). MSYS Git Bash on Windows also ships without `jq`; the upstream Stop hook can't parse transcripts there.
- **Tab-by-tab support matrix** documented in [`cowork-plugin/README.md`](cowork-plugin/README.md). The Cowork app has three runtimes (Chat / Cowork-VM / Code) with different plugin behaviors; this port ships full functionality in the Code tab and degrades gracefully in the Cowork-VM tab (per [anthropics/claude-code#27398](https://github.com/anthropics/claude-code/issues/27398) and [#40495](https://github.com/anthropics/claude-code/issues/40495)).

## Install

Add this repo as a marketplace in the Cowork app (Customize → Add marketplace → paste the repo URL), then install the **claude-code-handoff** plugin from it. See [`cowork-plugin/README.md`](cowork-plugin/README.md) for the full install/limitations writeup and the tab-by-tab support table.

If you want the original (non-Cowork) install path — symlinks into `~/.claude/` and a `jq`-driven `install.sh` settings.json patch — use **[Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff)** directly. That's the upstream and it's the right answer for the standalone Claude Code CLI.

## License

[MIT](LICENSE). Copyright (c) 2026 Christopher Chadwick (upstream). This port adds packaging and portability shims under the same license.

## Credits

- **Christopher Chadwick** ([@Sting25](https://github.com/Sting25)) — upstream author of [claude-code-handoff](https://github.com/Sting25/claude-code-handoff). All snapshot/skill logic is his work.
- **Scott Converse** — this Cowork-installable packaging.
