#!/usr/bin/env bash
# Installs the title-only `commit` skill for Claude Code at user (system) level.
# Idempotent: re-run any time to resync with the repo; unchanged files are left alone.
#
#   curl -fsSL https://raw.githubusercontent.com/elvisgastelum/claude-commit-skill/main/install.sh | bash
#
# Options (env vars):
#   CLAUDE_DIR=~/.claude   target Claude config directory
#   REPO=owner/name        GitHub repo to download from
#   REF=main               branch or tag to download from
#   SKIP_SETTINGS=1        do not touch settings.json (skill and instructions only)
#
# Uninstall:
#   curl -fsSL .../install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="${REPO:-elvisgastelum/claude-commit-skill}"
REF="${REF:-main}"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
RAW="https://raw.githubusercontent.com/$REPO/$REF"

SKILL_DIR="$CLAUDE_DIR/skills/commit"
HOOK_PATH="$CLAUDE_DIR/hooks/commit-guard.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
MEMORY="$CLAUDE_DIR/CLAUDE.md"
BLOCK_BEGIN="<!-- BEGIN claude-commit-skill: managed by install.sh, edits inside this block are overwritten -->"
BLOCK_END="<!-- END claude-commit-skill -->"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-commit-skill.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# Use local files when run from a clone, otherwise download them.
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/skills/commit/SKILL.md" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

fetch() { # fetch <repo-relative-path> <dest>
  mkdir -p "$(dirname "$2")"
  if [ -n "$SRC_DIR" ]; then
    cp "$SRC_DIR/$1" "$2"
  else
    curl -fsSL "$RAW/$1" -o "$2" || die "failed to download $RAW/$1"
  fi
}

replace_if_changed() { # replace_if_changed <new> <dest>: back up and rewrite dest only when content differs
  if [ -f "$2" ] && cmp -s "$1" "$2"; then
    return 1
  fi
  [ -f "$2" ] && cp "$2" "$2.bak.$(date +%Y%m%d%H%M%S)"
  # Write through instead of mv so a symlinked dest (e.g. from a dotfiles repo) stays a symlink.
  cat "$1" > "$2"
}

update_settings() { # update_settings <jq filter>
  local tmp="$TMP_DIR/settings.json"
  jq "$1" --arg hook "$HOOK_PATH" "$SETTINGS" > "$tmp" || die "failed to update $SETTINGS"
  replace_if_changed "$tmp" "$SETTINGS" || info "$SETTINGS already up to date"
}

check_block_markers() { # exits unless MEMORY has no block or exactly one well-formed block
  [ -f "$MEMORY" ] || return 0
  local b e
  b="$(grep -Fxc "$BLOCK_BEGIN" "$MEMORY" || true)"
  e="$(grep -Fxc "$BLOCK_END" "$MEMORY" || true)"
  [ "$b" = 0 ] && [ "$e" = 0 ] && return 0
  if [ "$b" = 1 ] && [ "$e" = 1 ] \
    && [ "$(grep -Fxn "$BLOCK_BEGIN" "$MEMORY" | cut -d: -f1)" -lt "$(grep -Fxn "$BLOCK_END" "$MEMORY" | cut -d: -f1)" ]; then
    return 0
  fi
  die "$MEMORY has a damaged claude-commit-skill block; fix the BEGIN/END markers and re-run."
}

sync_instructions() { # writes instructions/attribution.md into a managed block of ~/.claude/CLAUDE.md
  local src="$TMP_DIR/attribution.md" tmp="$TMP_DIR/CLAUDE.md"
  check_block_markers
  fetch instructions/attribution.md "$src"
  [ -z "$(tail -c 1 "$src")" ] || echo >> "$src"
  if [ -f "$MEMORY" ] && grep -Fxq "$BLOCK_BEGIN" "$MEMORY"; then
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" -v src="$src" '
      $0 == b { print; while ((getline l < src) > 0) print l; skip = 1; next }
      $0 == e { skip = 0 }
      !skip   { print }' "$MEMORY" > "$tmp"
  else
    if [ -s "$MEMORY" ]; then
      cat "$MEMORY" > "$tmp"
      [ -z "$(tail -c 1 "$MEMORY")" ] || echo >> "$tmp"
      echo >> "$tmp"
    fi
    { echo "$BLOCK_BEGIN"; cat "$src"; echo "$BLOCK_END"; } >> "$tmp"
  fi
  mkdir -p "$CLAUDE_DIR"
  if replace_if_changed "$tmp" "$MEMORY"; then
    info "Synced attribution instructions into $MEMORY"
  else
    info "$MEMORY instructions already up to date"
  fi
}

remove_instructions() {
  [ -f "$MEMORY" ] && grep -Fxq "$BLOCK_BEGIN" "$MEMORY" || return 0
  local tmp="$TMP_DIR/CLAUDE.md"
  awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
    $0 == b { skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { line[++n] = $0 }
    END     { while (n > 0 && line[n] == "") n--; for (i = 1; i <= n; i++) print line[i] }' "$MEMORY" > "$tmp"
  replace_if_changed "$tmp" "$MEMORY" || true
  info "Removed attribution instructions from $MEMORY"
}

uninstall() {
  check_block_markers # fail before removing anything, so a damaged block never leaves a partial uninstall
  info "Removing $SKILL_DIR and $HOOK_PATH"
  rm -rf "$SKILL_DIR"
  rm -f "$HOOK_PATH"
  remove_instructions
  if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    update_settings '
      if .hooks.PreToolUse then
        .hooks.PreToolUse |= (map(.hooks |= map(select(.command != $hook))) | map(select(.hooks | length > 0)))
      else . end'
    info "Removed commit-guard hook from $SETTINGS (attribution setting left as is)"
  fi
  info "Uninstalled."
}

install() {
  info "Installing commit skill to $SKILL_DIR"
  fetch skills/commit/SKILL.md "$SKILL_DIR/SKILL.md"
  sync_instructions

  if [ "${SKIP_SETTINGS:-0}" = "1" ]; then
    info "SKIP_SETTINGS=1: skipping hook and settings.json changes."
    info "Done. Restart Claude Code to load the skill."
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found: installed the skill only."
    warn "For full enforcement add to $SETTINGS:  \"attribution\": {\"commit\": \"\", \"pr\": \"\"}"
    return
  fi

  info "Installing commit-guard hook to $HOOK_PATH"
  fetch hooks/commit-guard.sh "$HOOK_PATH"
  chmod +x "$HOOK_PATH"

  mkdir -p "$CLAUDE_DIR"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS is not valid JSON; fix it and re-run."

  info "Disabling Claude commit and PR attribution and registering the hook in $SETTINGS"
  update_settings '
    .attribution = ((.attribution // {}) + {commit: "", pr: ""})
    | .includeCoAuthoredBy = false
    | .hooks = (.hooks // {})
    | .hooks.PreToolUse = (
        ((.hooks.PreToolUse // []) | map(.hooks |= map(select(.command != $hook))) | map(select(.hooks | length > 0)))
        + [{matcher: "Bash", hooks: [{type: "command", command: $hook}]}]
      )'

  info "Done. Restart Claude Code to load the skill and settings."
}

case "${1:-}" in
  --uninstall|uninstall) uninstall ;;
  ""|--install|install) install ;;
  *) die "unknown argument: $1 (use --uninstall)" ;;
esac
