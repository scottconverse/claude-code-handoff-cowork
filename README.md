# claude-code-handoff-cowork

> **A Cowork-installable port of [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) by Christopher Chadwick.**
>
> The original tool — the snapshot logic, the transcript appender, the `/handoff` skill spec — is **his** work, used here under MIT. This repo packages it for the Claude Cowork desktop app and replaces two host-side dependencies (`jq`, `flock`) with portable equivalents so it runs on Windows MSYS Git Bash without extra installs.

---

## The problem this solves

Claude Code sessions hit a context limit. When they do, the next session starts blind — you re-explain the project, the in-flight track, the decisions you made twenty minutes ago, all from memory. The model has no continuity. You become the continuity.

Christopher Chadwick wrote `claude-code-handoff` to fix this:

- **`SessionEnd` hook** snapshots `HEAD`, branch, recent commits, working-tree state, and in-flight `.md` docs to `<repo>/.claude/handoff_current.md`.
- **`SessionStart` hook** in the next session reads that file and injects it as context. No prompt to remember.
- **`Stop` hook** after every turn appends the new transcript lines to a raw-dump backup. Saturated-context restart-from-thin-curated-notes failure mode goes away.
- **`/handoff` slash command** lets you trigger a snapshot manually at clean boundaries with a curated `## Notes from this session` block and a loud banner telling you to actually start a new session.

The next session is no longer blind. That's the whole pitch.

## What this repo adds

The upstream project installs via `git clone + ./install.sh`, which patches your `~/.claude/settings.json` with `jq` and uses `flock` for Stop-hook serialization. That's correct for the standalone Claude Code CLI on Linux/macOS. It doesn't fit two real-world surfaces:

1. **The Cowork desktop app.** Users install plugins through Customize → Browse plugins, not by running shell scripts. The Cowork app's plugin loader reads `.claude-plugin/plugin.json` and `hooks/hooks.json`, not patched user settings.
2. **Windows MSYS Git Bash.** The shell that runs hook commands inside Cowork's Code tab. Neither `jq` nor `flock` ships there by default.

This port:

- Packages the upstream code as a single-plugin **marketplace** (`.claude-plugin/marketplace.json`) installable through the Cowork app's UI.
- Replaces `jq` with **`bin/handoff_turn_format.pl`** — a Perl helper using only `JSON::PP` (a core module since 5.14). Same per-line parse, same output shape.
- Replaces `flock` with an atomic **`mkdir`-based lock**. Same serialization guarantees, works on every platform.
- Adds a **three-tier fallback** for resolving the active session and transcript path: JSON stdin payload (upstream contract) → `CLAUDE_ENV_FILE` path-parse → `CLAUDE_PROJECT_DIR` → encoded `~/.claude/projects/<encoded>/<sid>.jsonl`. This makes the plugin work in headless `claude -p` mode (where stdin is empty) as well as interactive mode.
- Adds **`CLAUDE_PROJECT_DIR`-preferred repo resolution** in both scripts. The Cowork app's Code-tab sessions root the shell at `C:\Users\scott\.klodock`, not the user's project; `git rev-parse` from pwd doesn't work, but `CLAUDE_PROJECT_DIR` does.
- Adds **`bin/probe_hook.sh`** — a diagnostic env-logger wired ahead of each real hook. Writes to `~/handoff_probe.log` for troubleshooting.

That's it. Snapshot semantics, output formats, skill triggers, `HANDOFF_*` configuration env vars — all unchanged from upstream.

## Verified

End-to-end on Windows 11 + MSYS Git Bash + Claude Code 2.1.87 (real `claude -p` headless run, real Anthropic API turn): all three hooks fired, both artifacts written, the raw dump contained the actual model conversation. Full receipts including probe-log captures and exact commit SHAs in **[`docs/VERIFICATION.md`](docs/VERIFICATION.md)**.

## Install

In the Cowork desktop app:

1. **Customize → Browse plugins → Add marketplace.**
2. Paste `https://github.com/scottconverse/claude-code-handoff-cowork`.
3. Install **claude-code-handoff** from the marketplace.
4. Start a fresh Code-tab session in any git repo. The `/handoff` skill appears in the `/` menu.

For file-level install (when the UI doesn't help) and full daily-use guidance: **[`USER-MANUAL.md`](USER-MANUAL.md)**.

## Tab support matrix

| Cowork tab | `/handoff` skill | `SessionStart` auto-load | `SessionEnd` auto-write | `Stop` per-turn dump |
|------------|------------------|--------------------------|-------------------------|----------------------|
| **Chat**   | ✗ (no shell)     | ✗                        | ✗                       | ✗                    |
| **Cowork** | ✓                | ✗ (known bug)            | ✗                       | ✗                    |
| **Code**   | ✓                | ✓                        | ✓                       | ✓                    |

The Cowork-VM tab hooks-don't-fire issue is upstream Anthropic bugs [#27398](https://github.com/anthropics/claude-code/issues/27398) and [#40495](https://github.com/anthropics/claude-code/issues/40495), not a port issue — affects every marketplace plugin with hooks. The `/handoff` skill itself loads fine there; use it manually.

## Documentation

- **[USER-MANUAL.md](USER-MANUAL.md)** — install, daily use, env vars, troubleshooting.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — hook lifecycle, cwd-resolution decision tree, fallback chain, manifest schemas.
- **[CHANGELOG.md](CHANGELOG.md)** — what shipped in 0.1.0.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — where bug reports and PRs should go (upstream vs here).
- **[CREDITS.md](CREDITS.md)** — per-file attribution.
- **[docs/VERIFICATION.md](docs/VERIFICATION.md)** — end-to-end test receipts.

## Bug reports

- **Plugin / Cowork-install / MSYS-portability** issues → [this repo's Issues](https://github.com/scottconverse/claude-code-handoff-cowork/issues).
- **Snapshot logic / skill spec / output format** issues → [upstream's Issues](https://github.com/Sting25/claude-code-handoff/issues). That's Christopher's domain; the logic is unchanged here.
- **Cowork app / Claude Code CLI** issues (hooks not firing, etc.) → [anthropics/claude-code/issues](https://github.com/anthropics/claude-code/issues).

## Discuss

[GitHub Discussions](https://github.com/scottconverse/claude-code-handoff-cowork/discussions) — questions, showcase, ideas.

## Credit

**Christopher Chadwick** ([@Sting25](https://github.com/Sting25)) is the author of [claude-code-handoff](https://github.com/Sting25/claude-code-handoff). The snapshot script, the transcript appender, the `/handoff` skill, the substrate pattern, the entire idea — all his work. This port stands on his shoulders. If this is useful to you, [his repo](https://github.com/Sting25/claude-code-handoff) is the place to go for context, upstream development, and credit.

**Scott Converse** ([@scottconverse](https://github.com/scottconverse)) packaged Christopher's work for the Cowork app, wrote the MSYS portability shims, and added the env-fallback chain for headless mode.

## License

[MIT](LICENSE). Copyright (c) 2026 Christopher Chadwick, preserved verbatim from upstream. The port additions are under the same license.
