# Contributing

This is a **port**. Upstream is [Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff) by Christopher Chadwick — that's where the snapshot logic, transcript parser, and `/handoff` skill spec live.

## Where should your change go?

**Upstream ([Sting25/claude-code-handoff](https://github.com/Sting25/claude-code-handoff))**:
- Snapshot script logic (`bin/write_handoff.sh`).
- Transcript appender logic (`bin/handoff_turn_append.sh`) other than the port-specific shims (mkdir-lock, perl JSON helper, env-fallback).
- The `/handoff` skill spec (triggers, banner format, "Raw dump fallback" workflow).
- `HANDOFF_*` env var semantics.
- Output shape of `handoff_current.md` and `handoff_raw_*.md`.
- New features that should benefit both the standalone-CLI install and the Cowork install.

**Here (scottconverse/claude-code-handoff-cowork)**:
- `cowork-plugin/.claude-plugin/plugin.json` (plugin manifest).
- `.claude-plugin/marketplace.json` (marketplace manifest).
- `cowork-plugin/hooks/hooks.json` (declarative hook wiring).
- `cowork-plugin/bin/handoff_turn_format.pl` (jq-replacement Perl helper).
- The mkdir-lock + env-fallback chain in `handoff_turn_append.sh`.
- The `CLAUDE_PROJECT_DIR`-preferred repo resolution in both scripts.
- Cowork-app-specific documentation (tab support matrix, `.klodock` cwd notes).
- `probe_hook.sh` diagnostic logger.

When in doubt: if the change would help someone running upstream's `install.sh` against the standalone Claude Code CLI on Linux/macOS, send it upstream. If it's specific to the Cowork desktop app or to MSYS Git Bash on Windows, send it here.

## Local development

```bash
git clone https://github.com/scottconverse/claude-code-handoff-cowork.git
cd claude-code-handoff-cowork
# Validate manifests
claude plugin validate cowork-plugin/.claude-plugin/plugin.json
claude plugin validate .claude-plugin/marketplace.json
# Syntax-check shell + perl
bash -n cowork-plugin/bin/write_handoff.sh
bash -n cowork-plugin/bin/handoff_turn_append.sh
perl -c cowork-plugin/bin/handoff_turn_format.pl
```

## Testing changes against a real Claude Code session

The plugin needs to fire hooks against a real `claude` binary to be meaningfully tested. Two paths:

**Headless** (cheapest, fastest, works on any machine with `claude` installed and an Anthropic API key):

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
# Point CLAUDE_PROJECT_DIR somewhere with a git repo:
cd /path/to/some/git/repo
rm -f ~/handoff_probe.log
rm -rf .claude/handoff_current.md .claude/handoff_backups
claude -p "Reply: ok" < /dev/null
# Inspect:
cat ~/handoff_probe.log         # which hooks fired, what env they saw
cat .claude/handoff_current.md  # SessionEnd output
ls .claude/handoff_backups/     # Stop hook output
```

**Interactive Cowork app**: install the plugin, open a Code-tab session against a git repo, run `/handoff`. Read `~/handoff_probe.log` to see the hook-context env.

## Code style

- **Bash:** `set -euo pipefail` (already in place). Use `[[ ]]` for tests. Lock with `mkdir` not `flock` (cross-platform).
- **Perl:** `use strict; use warnings;` and only Perl core modules (`JSON::PP` is fine, anything CPAN is not — keep zero install footprint).
- **No new external dependencies.** The whole point of this port is "works with what's already on the user's machine." If you need a tool that isn't already on MSYS Git Bash, find another way.
- **Test on Windows MSYS Git Bash** if your change touches the bin scripts. It's the most-restrictive surface and most other surfaces are supersets.

## Reporting issues

- **Plugin-specific issues** (manifest, hook wiring, MSYS/Windows behavior, Cowork-app install) → file in this repo's [Issues](https://github.com/scottconverse/claude-code-handoff-cowork/issues).
- **Upstream issues** (snapshot logic, skill spec, transcript parser semantics) → file in [Sting25/claude-code-handoff/issues](https://github.com/Sting25/claude-code-handoff/issues).
- **Cowork app / Claude Code CLI bugs** (hooks not firing, `--setting-sources` restrictions, sandbox env issues) → file in [anthropics/claude-code](https://github.com/anthropics/claude-code/issues).

## Credit

Christopher Chadwick wrote this. We packaged it for Cowork. Keep that obvious in any commit message, PR description, or doc change you make.
