#!/usr/bin/env bash
# Installs the title-only `commit` skill for Claude Code at user (system) level.
#
#   curl -fsSL https://raw.githubusercontent.com/elvisgastelum/claude-commit-skill/main/install.sh | bash
#
# Options (env vars):
#   CLAUDE_DIR=~/.claude   target Claude config directory
#   REPO=owner/name        GitHub repo to download from
#   REF=main               branch or tag to download from
#   SKIP_SETTINGS=1        do not touch settings.json (skill only)
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

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

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

backup_settings() {
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
}

update_settings() { # update_settings <jq filter>
  local tmp
  tmp="$(mktemp)"
  jq "$1" --arg hook "$HOOK_PATH" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

uninstall() {
  info "Removing $SKILL_DIR and $HOOK_PATH"
  rm -rf "$SKILL_DIR"
  rm -f "$HOOK_PATH"
  if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    backup_settings
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

  if [ "${SKIP_SETTINGS:-0}" = "1" ]; then
    info "SKIP_SETTINGS=1: skipping hook and settings.json changes."
    info "Done. Restart Claude Code to load the skill."
    return
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found: installed the skill only."
    warn "For full enforcement add to $SETTINGS:  \"attribution\": {\"commit\": \"\"}"
    return
  fi

  info "Installing commit-guard hook to $HOOK_PATH"
  fetch hooks/commit-guard.sh "$HOOK_PATH"
  chmod +x "$HOOK_PATH"

  mkdir -p "$CLAUDE_DIR"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  jq empty "$SETTINGS" 2>/dev/null || die "$SETTINGS is not valid JSON; fix it and re-run."
  backup_settings

  info "Disabling Claude commit attribution and registering the hook in $SETTINGS"
  update_settings '
    .attribution = ((.attribution // {}) + {commit: ""})
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
