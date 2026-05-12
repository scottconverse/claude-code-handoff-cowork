# User Manual

> **What this is.** A Cowork-installable port of [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) by Christopher Chadwick — a Claude Code skill + hooks that snapshot session state on exit and auto-load it on the next session's start, plus a `/handoff` slash command. The original idea, snapshot logic, and skill spec are all his work. This repo packages it as a Cowork-installable plugin.
>
> **Who this manual is for.** Anyone installing or operating the plugin inside the Cowork desktop app. If you're on the standalone Claude Code CLI (Linux/macOS terminal, no Cowork app), use [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) directly — its `install.sh` is the right path there.

---

## Contents

1. [What it does](#what-it-does)
2. [Install](#install)
3. [Daily use](#daily-use)
4. [Configuration (env vars)](#configuration-env-vars)
5. [Cowork app tab behavior](#cowork-app-tab-behavior)
6. [Troubleshooting](#troubleshooting)
7. [Uninstall](#uninstall)

---

## What it does

When you start a Code-tab session in the Cowork app:

- **`SessionStart` hook** reads `<repo>/.claude/handoff_current.md` (if it exists from a previous session) and injects it into your new session's context. No copy-paste, no kickoff prompt to write.
- **`Stop` hook** fires after every assistant turn. Reads the new lines that landed in the transcript JSONL since the previous Stop, formats them, and appends to `<repo>/.claude/handoff_backups/handoff_raw_<session_id>.md`. Keeps the 3 newest dumps; older ones are pruned automatically.
- **`SessionEnd` hook** runs `bin/write_handoff.sh` on session exit. Snapshots HEAD, branch, recent commits, working-tree state, in-flight `.md` docs, and writes `<repo>/.claude/handoff_current.md` for the next session to pick up.
- **`/handoff` skill** lets you trigger a snapshot manually at any clean boundary. Same write_handoff.sh script + the assistant appends a curated "Notes from this session" prose block + prints a deliberately loud `-*-*-` banner telling you to start a new session.

The point: **the next session is never blind**. You stop re-explaining the project, the in-flight track, and the decisions you made twenty minutes ago.

---

## Install

### Through the Cowork app (recommended)

1. Open the **Cowork** desktop app.
2. In the left sidebar, click **Customize**.
3. **Browse plugins** → **Add marketplace**.
4. Paste: `https://github.com/scottconverse/claude-code-handoff-cowork`
5. Find **claude-code-handoff** in the marketplace listing and click **Install**.
6. Verify it's enabled. Open a fresh Code-tab session in any git repo — the `/handoff` skill should appear in the `/` menu.

### File-level (if the marketplace UI fails)

If the Cowork app's plugin UI doesn't list it or you want to install from a clone:

```bash
# 1. Clone into the marketplaces dir
cd ~/.claude/plugins/marketplaces
git clone https://github.com/scottconverse/claude-code-handoff-cowork.git

# 2. Register the marketplace + install the plugin
claude plugin marketplace add ~/.claude/plugins/marketplaces/claude-code-handoff-cowork
claude plugin enable claude-code-handoff@claude-code-handoff-cowork

# 3. Verify
claude plugin list
#   ❯ claude-code-handoff@claude-code-handoff-cowork
#     Version: 0.1.0
#     Scope: user
#     Status: ✔ enabled
```

If `claude plugin list` shows `✘ disabled`, the enable step didn't take — re-run it. If `✘ failed to load`, check the validation output: `claude plugin validate ~/.claude/plugins/marketplaces/claude-code-handoff-cowork/cowork-plugin/.claude-plugin/plugin.json`.

### Prerequisites

These ship with every Claude Code surface; you shouldn't have to install anything:

- `bash` — for the hook command runner.
- `git` — for the snapshot script's repo state queries.
- `perl` (with `JSON::PP`, a core module since 5.14) — for the transcript JSONL parser.

**`jq` and `flock` are NOT required.** Upstream needs them; this port replaces them with portable equivalents (Perl `JSON::PP` and atomic `mkdir`).

---

## Daily use

### Auto, in the background

Once installed, you don't need to do anything. Open a Code-tab session in a git repo. Work. End the session. The handoff gets written automatically. Start the next session in the same repo. The handoff loads automatically at the top of the new session's context.

The raw-dump backup at `.claude/handoff_backups/handoff_raw_<session_id>.md` accumulates turn-by-turn while you work — that file exists in case the `/handoff` curated notes block turns out thin.

### Manual, at clean boundaries

Type `/handoff` (or pick it from the `/` menu) when:

- A commit just landed and you want a clean cut for the next session.
- A track wrapped up (spec shipped, plan approved, design decided).
- Your context meter is getting tight.
- You're stepping away for the day.

When you invoke `/handoff`, the assistant:

1. Runs the snapshot script.
2. Reads the snapshot, appends a curated `## Notes from this session` block under the placeholder (decisions made, in-flight tracks, open questions, "next session should start with X" notes).
3. Prints a loud `-*-*-` banner telling you to start a new session.
4. Stops. No "while we're here" cleanup, no "one more thing." The handoff is the boundary.

### The banner

```
-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
                 ASK: START A NEW SESSION NOW
-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-

handoff written to: <path>
raw dump written to: <path>

action: end this session, then start a fresh one in the same project.
        The SessionStart hook auto-loads the handoff into context.
        Do NOT resume / continue this saturated session — that defeats
        the purpose of the handoff.

-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
```

It's intentionally loud. The borders exist so you can't scroll past them. The skill instructs the assistant not to soften this — if you want it softer, edit `cowork-plugin/skills/handoff/SKILL.md` and reinstall.

---

## Configuration (env vars)

All of these are upstream's design — exposed unchanged. Set them in your shell rc (e.g. `~/.bashrc`) or a per-project `.envrc`.

| Variable | Default | Purpose |
|---|---|---|
| `HANDOFF_INFLIGHT_DIRS` | `docs` | Space-separated subdirs to scan for untracked/modified `.md` files. Example: `"docs design rfcs"`. |
| `HANDOFF_SUBSTRATE_NAME` | *(unset)* | Name of a sibling git repo to also snapshot (a shared decisions/RFCs repo, etc.). |
| `HANDOFF_SUBSTRATE_INFLIGHT_DIRS` | *(unset)* | Same as `HANDOFF_INFLIGHT_DIRS` but scoped to the substrate. |
| `HANDOFF_NO_GITIGNORE_BOOTSTRAP` | *(unset)* | Set to `1` to skip the auto-add of `.claude/handoff_current.md` into the project's `.gitignore`. |

### Substrate pattern

A "substrate" is a sibling git repo that holds cross-project state — shared decisions, RFCs, coordination ASKs between teams. The snapshot script will capture both the current repo AND the substrate so the next session sees both pictures at once. If you don't have a substrate, leave `HANDOFF_SUBSTRATE_NAME` unset and the snapshot just skips that section.

Example: project repos live at `~/code/projectA` and `~/code/projectB`, and a shared docs repo at `~/code/_shared` holds RFCs everyone references:

```bash
export HANDOFF_SUBSTRATE_NAME="_shared"
export HANDOFF_SUBSTRATE_INFLIGHT_DIRS="rfcs ASKS"
```

Now `/handoff` in projectA captures projectA's repo state AND `_shared`'s repo state.

---

## Cowork app tab behavior

The Cowork desktop app has three tabs and they run different runtimes. This plugin's behavior differs accordingly:

| Tab        | `/handoff` skill | `SessionStart` auto-load | `SessionEnd` auto-write | `Stop` per-turn dump |
|------------|------------------|--------------------------|-------------------------|----------------------|
| **Chat**   | ✗ (no shell)     | ✗                        | ✗                       | ✗                    |
| **Cowork** | ✓                | ✗ (known bug)            | ✗                       | ✗                    |
| **Code**   | ✓                | ✓                        | ✓                       | ✓                    |

**Code tab — full functionality.** This is where the plugin earns its keep. Standard host-side Claude Code with the normal plugin loader. All three hooks fire. The skill appears in the `/` menu.

**Cowork-VM tab — degraded.** The `/handoff` skill is available and works fine. The three hooks do NOT fire, per [anthropics/claude-code#27398](https://github.com/anthropics/claude-code/issues/27398) (the in-VM CLI is spawned with `--setting-sources user` which silently excludes plugin-scoped hooks) and [#40495](https://github.com/anthropics/claude-code/issues/40495) (user settings.json isn't mounted into the sandbox either). Not a port bug — affects every marketplace plugin with hooks. Use `/handoff` manually here at clean boundaries.

**Chat tab — no plugin behavior.** No shell, no hooks, no skill menu.

If/when Anthropic fixes the Cowork-VM hook bug, no plugin change is needed — the hooks will start firing.

---

## Troubleshooting

### `/handoff` isn't in the `/` menu

```bash
claude plugin list
```

If status is `✘ disabled`:

```bash
claude plugin enable claude-code-handoff@claude-code-handoff-cowork
```

If status is `✘ failed to load`:

```bash
claude plugin validate ~/.claude/plugins/marketplaces/claude-code-handoff-cowork/cowork-plugin/.claude-plugin/plugin.json
```

Read the error message. The most common cause is a schema-mismatch on a manifest field (Anthropic's schema is strict — e.g. `repository` must be a string, not an object).

If the plugin is enabled but the skill still doesn't appear: **start a fresh session.** Plugins register at session start. The currently-running session won't see a newly-enabled plugin.

### `/handoff` runs but writes nothing / writes to the wrong place

Check `~/handoff_probe.log` (the bundled diagnostic logger):

```bash
cat ~/handoff_probe.log
```

For each hook fire it captures: cwd, `CLAUDE_PROJECT_DIR`, `CLAUDE_PLUGIN_ROOT`, and `git rev-parse` results from both. If `CLAUDE_PROJECT_DIR` resolves to something that isn't your project (e.g. `.klodock`, Cowork's sandbox dir), the snapshot script will write to the wrong place.

The scripts prefer `CLAUDE_PROJECT_DIR` over the shell's pwd. If both are wrong, you've hit an edge case worth filing an issue about — paste the log output.

### Stop hook fires but no `handoff_raw_*.md` file appears

This was a real bug in early development — fixed in 0.1.0. If you see it post-0.1.0:

- Check the probe log for `stdin_bytes=N` in the Stop event. If `stdin_bytes=0`, your Claude Code is firing Stop hooks without the JSON payload (the documented contract). The plugin falls back to filesystem-based session discovery using `CLAUDE_PROJECT_DIR`. If the project dir's encoded subdir under `~/.claude/projects/` doesn't exist or is empty, that fallback fails too.
- Run `find ~/.claude/projects -name '*.jsonl' -mmin -5` to see what transcripts have been written recently. If nothing comes up, Claude Code isn't writing transcripts to the expected path.

### Snapshots are slow

The snapshot script does git operations only (rev-parse, log, status). It should run in well under a second. If it's slow, your `HANDOFF_INFLIGHT_DIRS` may be scanning huge directories. Reduce the scope:

```bash
export HANDOFF_INFLIGHT_DIRS="docs"   # default; trim if your docs/ dir is huge
```

### My handoff file is checked into git

The script auto-adds `.claude/handoff_current.md` to your project's `.gitignore` on first run. If yours predates that bootstrap, add it manually:

```bash
echo ".claude/handoff_current.md" >> .gitignore
echo ".claude/handoff_backups/" >> .gitignore
```

To disable the bootstrap entirely:

```bash
export HANDOFF_NO_GITIGNORE_BOOTSTRAP=1
```

---

## Uninstall

```bash
claude plugin disable claude-code-handoff@claude-code-handoff-cowork
claude plugin uninstall claude-code-handoff@claude-code-handoff-cowork
# Optional: remove the marketplace registration too
claude plugin marketplace remove claude-code-handoff-cowork
```

The `.claude/handoff_current.md` and `.claude/handoff_backups/` files inside your projects are left in place. Delete them manually if you want them gone.

---

## Credits

- **Christopher Chadwick** ([@Sting25](https://github.com/Sting25)) — upstream author of [claude-code-handoff](https://github.com/Sting25/claude-code-handoff). The snapshot logic, the transcript appender, the `/handoff` skill spec — all his work. This port stands on his shoulders.
- **Scott Converse** ([@scottconverse](https://github.com/scottconverse)) — Cowork packaging, MSYS portability shims, env-fallback chain for headless mode.

See [`CREDITS.md`](CREDITS.md) for per-file attribution.

License: [MIT](LICENSE). Copyright (c) 2026 Christopher Chadwick, preserved verbatim from upstream.
