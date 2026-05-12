# claude-code-handoff — Cowork plugin

This is the plugin directory of [scottconverse/claude-code-handoff-cowork](https://github.com/scottconverse/claude-code-handoff-cowork), a Cowork-installable port of **[Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff)** by Christopher Chadwick. All snapshot logic and the `/handoff` skill spec are his work, used under MIT — see [`../LICENSE`](../LICENSE) and [`../README.md`](../README.md) for full credits and what's-the-same / what's-new.

Same idea as upstream: snapshot session state on exit, auto-load it on the next session's start, plus a `/handoff` slash command for manual invocation at clean boundaries.

If you're on the standalone Claude Code CLI (not the Cowork app), use [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) directly — its `install.sh` is the right path there.

## What this plugin does

When installed, three hooks fire in the Claude Code lifecycle:

- **`SessionStart`** — if `<repo>/.claude/handoff_current.md` exists,
  prints it into the new session's context. No prompt to remember.
- **`SessionEnd`** — runs `bin/write_handoff.sh`, which snapshots
  HEAD, branch, recent commits, working tree, and in-flight `.md` docs
  to `<repo>/.claude/handoff_current.md`.
- **`Stop`** — after every assistant turn, appends the turn's
  user-message + assistant-text + tool calls to
  `<repo>/.claude/handoff_backups/handoff_raw_<session_id>.md` (kept
  to the 3 newest files). This is the safety net for sessions where
  `/handoff`'s curated `Notes from this session` block turns out thin.

Plus the `/handoff` slash command, which runs the snapshot manually,
appends a curated `## Notes from this session` block, and prints a
loud banner telling the user to start a new session.

## Install (via the Cowork app)

1. In the Cowork app's left sidebar, click **Customize**.
2. **Browse plugins** → **Add marketplace** → paste `https://github.com/scottconverse/claude-code-handoff-cowork`.
3. Find **claude-code-handoff** in the marketplace and click **Install**.
4. Start a fresh session in any tab — the `/handoff` skill should appear in the `/` menu.

## Where this plugin works (and where it doesn't)

The Cowork app has three tabs. They use different runtimes, and the
plugin's behavior differs accordingly:

| Tab        | Skill (`/handoff`) | SessionStart hook | SessionEnd hook | Stop hook |
| ---------- | ------------------ | ----------------- | --------------- | --------- |
| **Chat**   | ✗ (no shell)       | ✗                 | ✗               | ✗         |
| **Cowork** | ✓                  | ✗ (see below)     | ✗               | ✗         |
| **Code**   | ✓                  | ✓                 | ✓               | ✓         |

**Why the Cowork-VM tab degrades:** [anthropics/claude-code#27398](https://github.com/anthropics/claude-code/issues/27398)
and [#40495](https://github.com/anthropics/claude-code/issues/40495)
document that the in-VM CLI is spawned with `--setting-sources user`,
which silently excludes plugin-scoped hooks from settings resolution
— and that the user's `~/.claude/settings.json` isn't mounted into
the sandbox either, so the upstream user-hook install path is also
inert there. Skills, slash commands, and MCP servers from a plugin
*do* load in the Cowork VM (they come from `--plugin-dir`, not
settings resolution). So in the Cowork-VM tab you get the `/handoff`
skill but no auto-write on exit and no auto-load on start.

**In the Code tab everything works** — that's standard host-side
Claude Code with the normal plugin loader.

If/when Anthropic fixes the Cowork-VM hook bug, no plugin change is
needed; the hooks will start firing.

## Prerequisites

- `bash`, `git`, `perl` — all three are present on every Claude Code
  surface (MSYS Git Bash on Windows, system Perl on macOS, Ubuntu in
  the Cowork VM).
- **No `jq` or `flock` required.** This plugin's port replaces:
  - `jq` (used upstream for transcript JSONL parsing) → a bundled
    Perl helper (`bin/handoff_turn_format.pl`) that uses only
    `JSON::PP` (Perl core since 5.14).
  - `flock` (used upstream for serializing concurrent Stop hooks) →
    an atomic `mkdir`-based lock directory. Works the same on every
    platform.

This matters because MSYS Git Bash on Windows ships without `jq` or
`flock`; on those systems the upstream `install.sh` falls back to
"print the JSON snippet for manual paste" and the Stop-hook locking
silently fails.

## Layout

```
cowork-plugin/
├── .claude-plugin/
│   └── plugin.json              # manifest (name, version, etc.)
├── hooks/
│   └── hooks.json               # SessionStart / SessionEnd / Stop wiring
├── bin/
│   ├── write_handoff.sh         # snapshot script (unchanged from upstream)
│   ├── handoff_turn_append.sh   # Stop-hook bash wrapper (mkdir-lock)
│   └── handoff_turn_format.pl   # transcript JSONL → markdown (jq replacement)
├── skills/
│   └── handoff/
│       └── SKILL.md             # /handoff slash command spec
└── README.md                    # this file
```

The hook commands in `hooks/hooks.json` reference scripts via
`${CLAUDE_PLUGIN_ROOT}/bin/...` so the plugin is relocatable —
Claude Code resolves that to wherever the plugin is installed on disk.

## Configuration

Same env vars as upstream (set in your shell rc or a per-project
`.envrc`):

- `HANDOFF_INFLIGHT_DIRS` — space-separated subdirs to scan for
  untracked/modified `.md` files. Default `docs`. Example:
  `"docs design rfcs"`.
- `HANDOFF_SUBSTRATE_NAME` — name of a sibling git repo to also
  snapshot (a shared decisions/RFCs repo, for instance). Default
  empty.
- `HANDOFF_SUBSTRATE_INFLIGHT_DIRS` — same as above, scoped to the
  substrate. Default empty.
- `HANDOFF_NO_GITIGNORE_BOOTSTRAP=1` — skip the auto-add of
  `.claude/handoff_current.md` into the project's `.gitignore`.

## Known limitations

1. **Cowork-VM tab hooks don't fire** (see the table above). Use
   `/handoff` manually there.
2. **No `Stop` hook on context-exhaustion.** Claude Code can't fire a
   hook when context fills mid-turn. The `/handoff` skill is the
   manual escape hatch; the `Stop` hook (where it fires) makes
   sure the raw dump is incremental rather than written-all-at-once
   when the conversation is already saturated.
3. **`SessionEnd` only fires on explicit session exit**, not on
   `/clear`. Invoke `/handoff` manually before `/clear` if you need
   the snapshot.
4. **Per-repo.** If you switch projects mid-session, the handoff only
   captures the repo where you invoke. Run `/handoff` in each.
5. **Requires a git worktree.** Both scripts call `git
   rev-parse --show-toplevel` and exit cleanly outside a repo.

## Differences from the upstream Claude-Code-CLI install

| Aspect                  | Upstream `install.sh`                      | This plugin                                 |
| ----------------------- | ------------------------------------------ | ------------------------------------------- |
| Install target          | `~/.claude/{bin,skills}/` + `settings.json` | Cowork app's plugin cache, via UI           |
| Hook wiring             | Patches `~/.claude/settings.json` with `jq` | Declarative `hooks/hooks.json`              |
| `jq` required           | Yes (or paste JSON manually)                | No — Perl `JSON::PP`                        |
| `flock` required        | Yes                                         | No — `mkdir` lock                            |
| Symlinks                | Yes (edits in repo go live)                 | No — Cowork copies into its plugin cache    |
| Updates                 | `git pull`                                  | Reinstall via Cowork's plugin UI            |
| Cowork-VM-tab support   | Hooks don't fire (#40495)                   | Skill works; hooks don't (#27398, #40495)   |
| Code-tab support        | Full                                        | Full                                        |

## License

[MIT](../LICENSE), same as upstream.
