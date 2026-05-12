---
name: handoff
description: Snapshot session state to .claude/handoff_current.md (plus a raw-dump backup at .claude/handoff_backups/handoff_raw_<session_id>.md that the Stop hook has been appending to all session, when Stop hooks fire) and tell the user (loudly, with -*-*- borders) to start a new session. Use at clean boundaries (commit lands, track wraps), when the user signals context pressure ("getting long", "meter is full"), or whenever the user invokes /handoff. Blocks until the user actually starts a new session — do not start new work after invoking.
---

# /handoff — write a session handoff

Used at clean boundaries (after a commit, when a major track wraps),
when the user signals context pressure, or whenever the user invokes
`/handoff`. Hands the next session a complete state snapshot so
nothing gets lost across the restart boundary.

## What this skill does

1. **Snapshot state** — runs `${CLAUDE_PLUGIN_ROOT}/bin/write_handoff.sh`, which captures:
   - HEAD, branch, recent commits, working-tree state for the current repo
   - Same for an optional sibling "substrate" repo (configured via
     `HANDOFF_SUBSTRATE_NAME`, e.g. a shared decisions / RFCs repo)
   - In-flight (untracked or modified) `.md` docs under the configured
     directories (default: `docs/`; configurable via `HANDOFF_INFLIGHT_DIRS`)
   - The "verify state matches reality" command block
2. **Append session-specific intent** — the script's snapshot is git-state-only; the conversation knows things git doesn't (decisions made, in-flight ASKs, open questions, "next session should start with X" notes). Append those under the `## Notes from this session` section using Edit.
3. **Confirm the raw-dump backup exists** — if the `Stop` hook fired during this session, `handoff_turn_append.sh` has been appending turn-by-turn to `.claude/handoff_backups/handoff_raw_<session_id>.md`. Verify it: `ls -la .claude/handoff_backups/`. **In the Cowork-VM tab the Stop hook does not fire** (known issue, see plugin README), so the file will be missing — fall through to "Raw dump fallback" below.
4. **Print a loud, unmissable banner** — the ASK must be impossible to miss (the user specifically asked for this; do not soften).
5. **Stop**. Do not start new work after the banner. The session is over.

## Steps

1. Run via Bash:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/bin/write_handoff.sh"
   ```
   The script outputs the absolute path of the written handoff
   (`<repo-root>/.claude/handoff_current.md`).

2. Read the file you just wrote. Then Edit it to add a `## Notes from
   this session` body under the placeholder. Capture, in order of
   importance:
   - **Work product produced this session.** If a plan was approved,
     a spec was drafted, a design was decided, or any artifact beyond
     commits was produced — paste or faithfully summarize it here.
     The next session should not have to read chat history to find
     what was decided. This is the load-bearing item.
   - Decisions made this session that aren't in any commit.
   - In-flight tracks the next session should pick up.
   - Open questions the user hasn't answered yet.
   - "Don't do Y" / "Be careful about Z" cautions.
   - The literal commands the next session should run first to get
     oriented (often the verify-state block from the snapshot).
   Skip items already in the auto-snapshot (HEAD, dirty files, commit list).

3. **Verify the raw dump.** Run `ls -la <repo-root>/.claude/handoff_backups/`
   and confirm the current session's file is there. If **missing**, fall
   through to "Raw dump fallback" below. (In the Cowork-VM tab this will
   always be missing — that's expected; the SessionEnd and Stop hooks
   don't fire there.)

4. Print the banner verbatim. Do NOT skip, soften, or shrink this:

   ```
   -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
                    ASK: START A NEW SESSION NOW
   -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-

   handoff written to: <path the script printed>
   raw dump written to: <path of the raw-dump file>

   action:  end this session, then start a fresh one in the same project.
            The SessionStart hook auto-loads the handoff into context.
            Do NOT resume / continue this saturated session — that defeats
            the purpose of the handoff.

   -*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-
   ```

5. Stop. Do NOT continue working after printing the banner.

## Raw dump fallback

Use this only if the `Stop` hook is not firing (Cowork-VM tab, or hook
not installed) and the running raw-dump file is missing. Create the
dump in one shot, write it to
`<repo-root>/.claude/handoff_backups/handoff_raw_<timestamp>.md` (use
UTC `YYYY-MM-DD_HHMM`), and prune to 3 newest:

```bash
ls -t <repo-root>/.claude/handoff_backups/handoff_raw_*.md 2>/dev/null \
  | tail -n +4 \
  | xargs -r rm
```

Content guidance: long-form, lightly-edited brain dump — what we
worked on, what got decided (including the ones the user pushed back
on), what got built or written (paste plans/specs in full if
reasonable), what the user said about how to proceed (direct quotes
where phrasing matters), what's still open, what almost got missed.
Better to over-include than miss something. The dump is gitignored.

## When to invoke without being asked

The assistant cannot self-measure context % (`/context` is user-side).
Trigger on observable signals, not fabricated percentages.

### Trigger 1: clean boundary after meaningful work

After a commit lands, a track wraps, a spec ships, an ASK reply goes
out — if the boundary feels substantive, ask:

> Good handoff moment — want me to run /handoff, or keep going?

### Trigger 2: any user signal about context pressure

If the user mentions context, meter, percentage, "this is getting
long," "you must be running out," — immediately offer:

> Sounds like context is getting tight. Want me to run /handoff now?

### What NOT to trigger on

- A fabricated percentage. The assistant does not have access to the number.
- Mid-task interruption. Finish the in-flight edit first.
- Repeated asks at every tiny boundary.

## What NOT to do

- Do not invoke mid-task. Always wait for a commit / boundary.
- Do not invoke twice in a row.
- Do not "soften" the banner because it feels intrusive — it IS
  intrusive by design.
- Do not skip the raw dump.
- Empty `## Notes from this session` is acceptable ONLY for purely
  mechanical sessions (single bug fix, no decisions, no work product
  beyond commits). When in doubt, write the notes.
