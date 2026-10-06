#!/usr/bin/env bash
# PreToolUse hook for the Bash tool: blocks git commits whose message is not a single title line.
# Exit 2 tells Claude Code to block the call and show stderr to the model.
set -u

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Only act on `git [global opts] commit`.
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_-])git([[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+|--[a-z-]+(=[^[:space:]]+)?))*[[:space:]]+commit([[:space:]]|$)' || exit 0

block() {
  printf 'commit-guard: %s\nUse a single title line: git commit -m "type(scope): summary" (see the commit skill).\n' "$1" >&2
  exit 2
}

printf '%s' "$cmd" | grep -Eiq 'co-authored-by|generated with \[?claude' \
  && block 'commit attribution trailers (Co-Authored-By / Generated with Claude Code) are not allowed.'

printf '%s' "$cmd" | grep -Eq '<<|(^|[[:space:]])(-F|--file)([[:space:]=]|$)' \
  && block 'heredocs and -F/--file commit messages are not allowed.'

m_flags="$(printf '%s' "$cmd" | grep -Eo '(^|[[:space:]])(-[a-zA-Z]*m|--message)([[:space:]=]|$)' | wc -l | tr -d ' ')"
[ "${m_flags:-0}" -gt 1 ] && block 'multiple -m flags create a commit body.'

case "$cmd" in
  *$'\n'*) block 'multi-line commit commands are not allowed (the message must be one line).' ;;
esac

exit 0
