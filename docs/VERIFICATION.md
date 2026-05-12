# Verification

End-to-end test receipts for [claude-code-handoff-cowork](https://github.com/scottconverse/claude-code-handoff-cowork) 0.1.0. Ran on Windows 11 Pro, MSYS Git Bash, Claude Code CLI 2.1.87 / Claude Desktop 2.1.128.

The plugin under test is a Cowork-installable port of [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) by Christopher Chadwick. **All snapshot logic, skill spec, and transcript-appender semantics are his.** This file documents that the port's packaging, hook wiring, and platform shims work end-to-end against a real Claude Code session.

---

## Environment

- **OS:** Windows 11 Pro 10.0.26200 (`MINGW64_NT-10.0-26200 ... x86_64 Msys`)
- **Shell:** Git Bash on MSYS (`/usr/bin/bash`)
- **Tools available:** `bash`, `git`, `perl` (with `JSON::PP` core). **Not** available: `jq`, `flock` (this port's shims handle both gaps).
- **Claude Code CLI:** `2.1.87 (Claude Code)`
- **Claude Desktop / Cowork app:** `2.1.128` (per `CLAUDE_CODE_EXECPATH` in probe log)
- **Plugin under test:** `claude-code-handoff@claude-code-handoff-cowork` at version `0.1.0`

---

## Plugin load state

```
$ claude plugin list
  ❯ claude-code-handoff@claude-code-handoff-cowork
    Version: 0.1.0
    Scope: user
    Status: ✔ enabled
```

```
$ claude plugin validate cowork-plugin/.claude-plugin/plugin.json
Validating plugin manifest: ...\cowork-plugin\.claude-plugin\plugin.json
✔ Validation passed

$ claude plugin validate .claude-plugin/marketplace.json
Validating marketplace manifest: ...\.claude-plugin\marketplace.json
✔ Validation passed
```

---

## End-to-end test 1 — real model turn, all hooks fire

Cleared probe log + cleared test repo's `.claude/`. Sourced an API key from a temp file. Ran:

```bash
$ cd /tmp/cch                          # real git repo (cch clone)
$ claude -p "Reply: ok" < /dev/null
ok
```

### Probe log (`~/handoff_probe.log`)

All three hooks fired naturally during the lifecycle of that one-turn session:

```
[2026-05-12T19:47:40Z] event=SessionStart
  pwd=/tmp/cch
  CLAUDE_PROJECT_DIR=/c/Users/scott/AppData/Local/Temp/cch
  CLAUDE_PLUGIN_ROOT=/c/Users/scott/.claude/plugins/marketplaces/claude-code-handoff-cowork/cowork-plugin
  CLAUDE_CODE_ENTRYPOINT=claude-desktop
  CLAUDE_CODE_IS_COWORK=<empty>
  HOME=/c/Users/scott
  git_top_from_pwd=C:/Users/scott/AppData/Local/Temp/cch
  git_top_from_project_dir=C:/Users/scott/AppData/Local/Temp/cch

[2026-05-12T19:47:43Z] event=Stop
  pwd=/tmp/cch
  CLAUDE_PROJECT_DIR=/c/Users/scott/AppData/Local/Temp/cch
  CLAUDE_PLUGIN_ROOT=/c/Users/scott/.claude/plugins/marketplaces/claude-code-handoff-cowork/cowork-plugin
  CLAUDE_CODE_ENTRYPOINT=claude-desktop
  CLAUDE_CODE_IS_COWORK=<empty>
  HOME=/c/Users/scott
  git_top_from_pwd=C:/Users/scott/AppData/Local/Temp/cch
  git_top_from_project_dir=C:/Users/scott/AppData/Local/Temp/cch
  stdin_bytes=0

[2026-05-12T19:47:44Z] event=SessionEnd
  pwd=/tmp/cch
  CLAUDE_PROJECT_DIR=/c/Users/scott/AppData/Local/Temp/cch
  CLAUDE_PLUGIN_ROOT=/c/Users/scott/.claude/plugins/marketplaces/claude-code-handoff-cowork/cowork-plugin
  CLAUDE_CODE_ENTRYPOINT=claude-desktop
  CLAUDE_CODE_IS_COWORK=<empty>
  HOME=/c/Users/scott
  git_top_from_pwd=C:/Users/scott/AppData/Local/Temp/cch
  git_top_from_project_dir=C:/Users/scott/AppData/Local/Temp/cch
  stdin_bytes=0
```

Interpreting:
- **SessionStart fired**, saw correct `CLAUDE_PROJECT_DIR` (the test repo's path).
- **Stop fired**, with `stdin_bytes=0` — headless mode doesn't send the documented stdin payload, which is why the env+filesystem fallback chain in `handoff_turn_append.sh` exists.
- **SessionEnd fired** correctly.
- `git_top_from_project_dir` resolves to the correct repo in all three events.

### Output artifact 1: `handoff_current.md` (SessionEnd → write_handoff.sh)

```
$ ls -la /tmp/cch/.claude/handoff_current.md
-rw-r--r-- 1 scott 197609 1370 May 12 13:47 /tmp/cch/.claude/handoff_current.md
```

First 16 lines:

```markdown
# cch — session handoff (auto-generated)

**Generated:** 2026-05-12 19:47 UTC

Auto-written by the `claude-code-handoff` plugin's `write_handoff.sh`
(called from the `/handoff` skill + the `SessionEnd` hook in the
plugin's `hooks/hooks.json`). Auto-loaded into the next session by the
`SessionStart` hook in the same file. Always lives at
`<repo>/.claude/handoff_current.md`; overwritten on every handoff.
Older snapshots are not retained — use git history of this file for
archaeology.

---

## Repo: cch

**HEAD:** `ef20707` — Banner: recommend fresh `claude`, warn against `claude --continue`
```

Full file: 1370 bytes, contains git state (HEAD, branch, recent commits, working tree status), the verify-state block, and the `## Notes from this session` placeholder.

### Output artifact 2: `handoff_raw_*.md` (Stop hook → handoff_turn_format.pl)

```
$ ls -la /tmp/cch/.claude/handoff_backups/
total 9
-rw-r--r-- 1 scott 197609   2 May 12 13:47 .handoff_raw_79903833-345f-4e07-b91f-8ae297e7de23.cursor
-rw-r--r-- 1 scott 197609 607 May 12 13:47 handoff_raw_79903833-345f-4e07-b91f-8ae297e7de23.md
```

Cursor file present (the dedup mechanism that prevents double-appending across concurrent Stop fires). Dump file is 23 lines, contains the real conversation:

```markdown
# Raw session dump

**Session ID:** `79903833-345f-4e07-b91f-8ae297e7de23`
**Started:** 2026-05-12 19:47 UTC

_Auto-appended turn-by-turn by the Stop hook (`handoff_turn_append.sh`).
Each block below is one user message + the assistant response that
followed. Tool outputs are truncated to keep the file readable; the
full transcript lives at `/c/Users/scott/.claude/projects/C--Users-scott-AppData-Local-Temp-cch/79903833-345f-4e07-b91f-8ae297e7de23.jsonl`. Recurring system-reminder /
command-* noise has been stripped._

---

## Turn at 2026-05-12 19:47:43 UTC

**User:**

Reply: ok

**Assistant:**

ok
```

This is the load-bearing evidence: a real `User:` block and a real `Assistant:` block from the actual model turn that ran. The Perl helper correctly parsed the transcript JSONL; the filesystem fallback correctly resolved `CLAUDE_PROJECT_DIR` → encoded `~/.claude/projects/C--Users-scott-AppData-Local-Temp-cch/` → newest `.jsonl` → session_id derived from filename.

---

## End-to-end test 2 — synthetic Stop payload against a 280-line real transcript

Before the fallback chain existed, the upstream contract (JSON stdin payload) was tested directly to verify the Perl JSON helper and the dump-file initialization:

```bash
$ tx=$(find ~/.claude/projects/.../*.jsonl | head -1)
$ wc -l "$tx"
280 .../0a318488-98c3-46b9-9f13-e9f83060cb3f.jsonl

$ printf '{"session_id":"manual-stop-test","transcript_path":"%s"}' "$tx" \
    | bash cowork-plugin/bin/handoff_turn_append.sh

$ ls -la .claude/handoff_backups/
.handoff_raw_manual-stop-test.cursor   4 bytes
handoff_raw_manual-stop-test.md        14368 bytes (407 lines)
```

Dump file structure (sample):

```markdown
# Raw session dump

**Session ID:** `manual-stop-test`
...

## Turn at 2026-05-12 19:31 UTC

**Assistant:**

Reading the required files before anything else.

**Tool calls:**

- `Read` — {"file_path":"C:\\Users\\scott\\OneDrive\\Desktop\\Claude\\AgentSuiteLocal\\HANDOFF.md"}
...
```

Counts in the dump: **23 User blocks, 10 Assistant blocks, 29 Tool-call blocks** — covers the full 280-line transcript correctly. Confirms the JSON stdin path works end-to-end with a real transcript.

---

## Idempotency test — second fire on unchanged transcript

```bash
$ printf '{"session_id":"manual-stop-test","transcript_path":"%s"}' "$tx" \
    | bash cowork-plugin/bin/handoff_turn_append.sh
$ wc -l .claude/handoff_backups/handoff_raw_manual-stop-test.md
407 .claude/handoff_backups/handoff_raw_manual-stop-test.md
```

Same line count as after the first fire. The cursor file correctly detected "no new lines since previous fire" and no-op'd. No lock-dir leakage:

```bash
$ ls .claude/handoff_backups/ | grep lock
(empty)
```

The `mkdir`-based lock is correctly cleaned up by the script's `trap rmdir`.

---

## Static checks

All scripts pass static analysis:

```
$ bash -n cowork-plugin/bin/write_handoff.sh       # ok
$ bash -n cowork-plugin/bin/handoff_turn_append.sh # ok
$ perl -c cowork-plugin/bin/handoff_turn_format.pl # syntax OK

$ perl -MJSON::PP -e 'local $/; decode_json(<STDIN>);' < cowork-plugin/.claude-plugin/plugin.json
# (no output = valid JSON)

$ perl -MJSON::PP -e 'local $/; decode_json(<STDIN>);' < .claude-plugin/marketplace.json
# (no output = valid JSON)

$ perl -MJSON::PP -e 'local $/; decode_json(<STDIN>);' < cowork-plugin/hooks/hooks.json
# (no output = valid JSON)
```

---

## What's NOT verified on this machine

Two scenarios that can only be exercised by humans:

1. **Real interactive Cowork-app Code-tab session.** The Cowork app's UI cannot be driven by computer-use (the Claude app window is masked in screenshots — security filter on the agent's own host app). Headless `claude -p` runs against the same `claude.exe` binary the Cowork app spawns, but the interactive vs headless lifecycle MAY differ in subtle ways. The plugin's `bin/probe_hook.sh` is deployed to capture exactly what an interactive Cowork session sees in hook context — the first Cowork-app session run after install will write to `~/handoff_probe.log` with full evidence.

2. **Cowork-VM tab.** Hooks documented not to fire there per [anthropics/claude-code#27398](https://github.com/anthropics/claude-code/issues/27398) and [#40495](https://github.com/anthropics/claude-code/issues/40495). The skill itself should still load; the plugin degrades to manual-only there. Not tested because the failure mode is upstream-known.

---

## Commits that landed each fix

| Commit | Change | Evidence in this doc |
|---|---|---|
| [`b71d9ba`](https://github.com/scottconverse/claude-code-handoff-cowork/commit/b71d9ba) | Add `probe_hook.sh` env logger | All probe-log excerpts above |
| [`fb35b6c`](https://github.com/scottconverse/claude-code-handoff-cowork/commit/fb35b6c) | Fix schema: remove `contributors` (not allowed) | `claude plugin validate` ✔ passed |
| [`e938a0b`](https://github.com/scottconverse/claude-code-handoff-cowork/commit/e938a0b) | Prefer `CLAUDE_PROJECT_DIR` over pwd | `git_top_from_project_dir` resolves correctly across all three events |
| [`41764f5`](https://github.com/scottconverse/claude-code-handoff-cowork/commit/41764f5) | Document cwd-resolution decision | `cowork-plugin/README.md` |
| [`feecc97`](https://github.com/scottconverse/claude-code-handoff-cowork/commit/feecc97) | Stop-hook env-fallback chain (the load-bearing fix) | Real-conversation dump in Test 1 |

---

## Reproducing this verification

```bash
# Prereqs: bash, git, perl, and `claude` (any Claude Code install)
# Plus an ANTHROPIC_API_KEY env var (not committed)

git clone https://github.com/scottconverse/claude-code-handoff-cowork.git ~/.claude/plugins/marketplaces/claude-code-handoff-cowork
claude plugin marketplace add ~/.claude/plugins/marketplaces/claude-code-handoff-cowork
claude plugin enable claude-code-handoff@claude-code-handoff-cowork
claude plugin list  # confirm ✔ enabled

# Run E2E
cd /path/to/some/git/repo
rm -f ~/handoff_probe.log
rm -rf .claude/handoff_current.md .claude/handoff_backups
export ANTHROPIC_API_KEY="sk-ant-..."
claude -p "Reply: ok" < /dev/null

# Inspect
cat ~/handoff_probe.log
cat .claude/handoff_current.md
ls -la .claude/handoff_backups/
head -25 .claude/handoff_backups/handoff_raw_*.md
```

If your output looks materially different from this document's, file an issue with the probe log attached.
