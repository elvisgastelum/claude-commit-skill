# claude-commit-skill

A user-level [Claude Code](https://claude.com/claude-code) skill that makes Claude commit with **one title line only**: no body, no trailers, no `Co-Authored-By: Claude ...`.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/elvisgastelum/claude-commit-skill/main/install.sh | bash
```

Restart Claude Code afterwards. The installer is idempotent: re-run the same command any time to resync with the repo. Files whose content already matches are left untouched and get no backup.

## What it installs

| Piece | Location | Purpose |
| --- | --- | --- |
| `commit` skill | `~/.claude/skills/commit/SKILL.md` | Auto-invoked whenever Claude is about to commit; defines the title-only rules. |
| attribution instructions | `~/.claude/CLAUDE.md` | A managed block (between `BEGIN/END claude-commit-skill` markers) synced from `instructions/attribution.md`: no `Generated with Claude Code` footer and no AI metadata in commits or PRs. Re-runs replace the block in place; the rest of the file is kept. |
| `commit-guard` hook | `~/.claude/hooks/commit-guard.sh` | `PreToolUse` hook on `Bash` that blocks `git commit` with trailers, heredocs, `-F`, multiple `-m`, or multi-line messages. |
| settings | `~/.claude/settings.json` | Sets `attribution.commit` and `attribution.pr` to `""` (and legacy `includeCoAuthoredBy: false`) so Claude Code stops asking for co-author lines and the PR footer. A timestamped backup is written first. |

The skill tells Claude what to do; the setting removes the conflicting attribution instruction; the hook enforces it.

## Options

```bash
# Skill and instructions only, leave settings.json untouched
curl -fsSL .../install.sh | SKIP_SETTINGS=1 bash

# Install from a fork or tag
curl -fsSL .../install.sh | REPO=you/claude-commit-skill REF=v1.0.0 bash

# Custom Claude config directory
curl -fsSL .../install.sh | CLAUDE_DIR=/path/to/.claude bash
```

Requires `bash` and `curl`; `jq` is needed for the hook and settings changes (without it, only the skill is installed).

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/elvisgastelum/claude-commit-skill/main/install.sh | bash -s -- --uninstall
```

Removes the skill, the hook file, the hook entry, and the managed block in `~/.claude/CLAUDE.md`. The `attribution` setting is left as is.

## Local development

```bash
git clone https://github.com/elvisgastelum/claude-commit-skill
cd claude-commit-skill
./install.sh   # copies local files instead of downloading
```
