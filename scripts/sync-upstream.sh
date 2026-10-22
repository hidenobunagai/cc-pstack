#!/usr/bin/env bash
# Pull a new upstream pstack Claude Code tree onto the `upstream` bookmark.
#
# The `upstream` bookmark holds the untouched upstream tree. Local adaptations are commits on top.
# This script adds a new upstream import commit on top of `upstream` and moves the bookmark.
# It never touches the local commits; rebase them afterwards (the script prints the command).
#
# Usage:
#   scripts/sync-upstream.sh            import upstream main onto the `upstream` bookmark
#   scripts/sync-upstream.sh --check    report changed files, write nothing
#   scripts/sync-upstream.sh --ref <r>  use another ref (default: main)
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
upstream_url="https://github.com/cursor/plugins.git"
tree="harness/pstack/claude-code"
ref=main
check=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=1; shift ;;
    --ref) ref="$2"; shift 2 ;;
    -h|--help) sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

work=$(mktemp -d)
ws_name="upstream-sync-$$"
cleanup() {
  jj -R "$repo_root" abandon --quiet "$ws_name@" >/dev/null 2>&1 || true
  jj -R "$repo_root" workspace forget "$ws_name" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

git clone --quiet --depth 1 --filter=blob:none --sparse --branch "$ref" "$upstream_url" "$work/src"
git -C "$work/src" sparse-checkout set "$tree" >/dev/null
src="$work/src/$tree"
upstream_sha=$(git -C "$work/src" rev-parse --short HEAD)
version=$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$src/plugin.json" | head -1)

# Files that are local to this fork and never come from upstream.
excludes=(--exclude .jj --exclude .git --exclude .gitignore --exclude .claude-plugin/marketplace.json --exclude node_modules)

jj -R "$repo_root" workspace add --quiet --name "$ws_name" -r upstream "$work/ws"
rsync -a --delete "${excludes[@]}" "$src/" "$work/ws/"

if [ -z "$(jj -R "$work/ws" diff --summary)" ]; then
  echo "upstream $version ($upstream_sha): no changes since the last import"
  exit 0
fi

echo "upstream $version ($upstream_sha) changes:"
jj -R "$work/ws" diff --summary | sed 's/^/  /'

[ "$check" = 1 ] && exit 0

jj -R "$work/ws" commit --quiet -m "Import upstream pstack $version Claude Code tree (cursor/plugins $upstream_sha)"
jj -R "$repo_root" bookmark set upstream -r "$ws_name@-" --quiet

cat <<'EOF2'

Moved the upstream bookmark. Rebase the local adaptations onto it:
  jj rebase -s 'roots(::main ~ ::upstream)' -d upstream
Then resolve conflicts, re-check docs/harness/claude-code.md against the new upstream rows,
and bump the version in .claude-plugin/plugin.json.
EOF2
