#!/usr/bin/env bash
# Exercises install.sh against throwaway CLAUDE_DIRs. Requires jq.
#   ./tests/install_test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
BEGIN_RE='^<!-- BEGIN claude-commit-skill'
FAILS=0

pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }

run() { CLAUDE_DIR="$1" "$ROOT/install.sh" "${@:2}" >/dev/null 2>&1; }
fresh() { rm -rf "$WORK/$1"; mkdir -p "$WORK/$1"; echo "$WORK/$1"; }
backups() { find "$1" -maxdepth 1 -name '*.bak.*' | wc -l | tr -d ' '; }

# Fresh install into an empty dir.
d="$(fresh empty)"
run "$d"
check "fresh install creates the managed block" "grep -q '$BEGIN_RE' '$d/CLAUDE.md'"
check "fresh install sets attribution.pr" "[ \"\$(jq -r .attribution.pr '$d/settings.json')\" = '' ]"

# Re-run is a no-op.
d="$(fresh rerun)"
printf '# my rules\nkeep me\n' > "$d/CLAUDE.md"
echo '{"model":"opus"}' > "$d/settings.json"
run "$d"
before="$(cat "$d/CLAUDE.md" "$d/settings.json" | cksum)"
n="$(backups "$d")"
run "$d"
check "re-run leaves files unchanged" "[ \"\$(cat '$d/CLAUDE.md' '$d/settings.json' | cksum)\" = '$before' ]"
check "re-run makes no new backups" "[ \"\$(backups '$d')\" = '$n' ]"
check "existing content and settings are kept" "grep -qx 'keep me' '$d/CLAUDE.md' && [ \"\$(jq -r .model '$d/settings.json')\" = opus ]"
check "exactly one managed block" "[ \"\$(grep -c '$BEGIN_RE' '$d/CLAUDE.md')\" = 1 ]"

# Edits inside the block are resynced.
sed -i.tmp 's/NEVER add/sometimes add/' "$d/CLAUDE.md" && rm -f "$d/CLAUDE.md.tmp"
run "$d"
check "edits inside the block are overwritten" "[ \"\$(cat '$d/CLAUDE.md' '$d/settings.json' | cksum)\" = '$before' ]"

# Install then uninstall restores the original file.
d="$(fresh roundtrip)"
printf '# my rules\nkeep me\n' > "$d/CLAUDE.md"
cp "$d/CLAUDE.md" "$WORK/orig.md"
run "$d" && run "$d" --uninstall
check "install + uninstall restores CLAUDE.md" "cmp -s '$WORK/orig.md' '$d/CLAUDE.md'"
check "uninstall removes skill and hook" "[ ! -e '$d/skills/commit' ] && [ ! -e '$d/hooks/commit-guard.sh' ]"

# A file without a trailing newline gets the block on its own lines.
d="$(fresh nonewline)"
printf 'no newline' > "$d/CLAUDE.md"
run "$d"
check "unterminated file keeps its last line intact" "grep -qx 'no newline' '$d/CLAUDE.md'"

# Symlinked files stay symlinks.
d="$(fresh symlink)"
mkdir -p "$WORK/dotfiles"
printf '# dotfiles\n' > "$WORK/dotfiles/CLAUDE.md"
echo '{}' > "$WORK/dotfiles/settings.json"
ln -s "$WORK/dotfiles/CLAUDE.md" "$d/CLAUDE.md"
ln -s "$WORK/dotfiles/settings.json" "$d/settings.json"
run "$d"
check "symlinked CLAUDE.md stays a symlink" "[ -L '$d/CLAUDE.md' ] && grep -q '$BEGIN_RE' '$WORK/dotfiles/CLAUDE.md'"
check "symlinked settings.json stays a symlink" "[ -L '$d/settings.json' ] && [ \"\$(jq -r .attribution.pr '$WORK/dotfiles/settings.json')\" = '' ]"

# Damaged markers stop install and uninstall before any change.
B='<!-- BEGIN claude-commit-skill: managed by install.sh, edits inside this block are overwritten -->'
E='<!-- END claude-commit-skill -->'
for name in missing-end reversed; do
  d="$(fresh "damaged-$name")"
  run "$d"
  case "$name" in
    missing-end) printf '%s\nx\n' "$B" > "$d/CLAUDE.md" ;;
    reversed)    printf '%s\nx\n%s\n' "$E" "$B" > "$d/CLAUDE.md" ;;
  esac
  cp "$d/CLAUDE.md" "$WORK/damaged.md"
  check "$name markers: install refuses" "! run '$d'"
  check "$name markers: uninstall refuses" "! run '$d' --uninstall"
  check "$name markers: nothing removed" "[ -f '$d/skills/commit/SKILL.md' ] && [ -f '$d/hooks/commit-guard.sh' ] && cmp -s '$WORK/damaged.md' '$d/CLAUDE.md'"
done

# No temp files leak, on success or failure.
mkdir -p "$WORK/tmp"
TMPDIR="$WORK/tmp" run "$(fresh tmpcheck)"
TMPDIR="$WORK/tmp" run "$WORK/damaged-missing-end"
check "no temp files left behind" "[ -z \"\$(ls -A '$WORK/tmp')\" ]"

echo
[ "$FAILS" = 0 ] && echo "all tests passed" || { echo "$FAILS test(s) failed"; exit 1; }
