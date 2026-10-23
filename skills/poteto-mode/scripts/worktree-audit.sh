#!/usr/bin/env bash
# Read-only workspace prune audit. Classifies every jj workspace by size, merge
# state, uncommitted work, remote/PR state, and the most recent chat that
# operated in it. Emits a table sorted by size with a suggested bucket. Never
# deletes anything; deletion stays a human-gated step in the playbook.
# Running jj in a workspace snapshots its working copy (an op-log entry, no
# file changes); that is the only write, and it is how jj sees uncommitted work.
#
# Usage: worktree-audit.sh [-b|--base <revset>] [repo-path]
#   repo-path defaults to the current repo.
#   -b sets the revset the MERGED column checks against (e.g. integration@origin).
#   Without it the base is trunk(), usually main@origin or master@origin.
#   trunk() is the remote's default branch, not necessarily the branch PRs
#   merge into; pass -b when they differ. Run `jj git fetch` first for fresh
#   remote state; this script does not fetch.
set -u

base=""
while [ $# -gt 0 ]; do
	case "$1" in
	-b|--base) [ $# -ge 2 ] || { echo "error: $1 needs a revset" >&2; exit 2; }; base="$2"; shift 2 ;;
	-h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
	-*) echo "error: unknown option: $1" >&2; exit 2 ;;
	*) break ;;
	esac
done

repo="${1:-$(jj workspace root 2>/dev/null)}"
[ -z "$repo" ] && { echo "not in a jj repo; pass a repo path" >&2; exit 1; }
cd "$repo" || exit 1
repo=$(jj workspace root 2>/dev/null) || { echo "error: not a jj repo: $repo" >&2; exit 1; }

jjq() { jj --color=never --no-pager "$@" 2>/dev/null; }

# Workspaces as "name<TAB>root". The default workspace is the main repo (it
# holds .git, so gh runs there); it and the one we run from are skipped.
workspaces=$(jjq workspace list --ignore-working-copy -T 'name ++ "\t" ++ root ++ "\n"')
main_wt=$(printf '%s\n' "$workspaces" | awk -F'\t' '$1=="default"{print $2; exit}')
[ -z "$main_wt" ] && main_wt="$repo"

if [ -z "$base" ]; then
	base="trunk()"
	echo "warn: no -b given; MERGED checks against trunk() ($(jjq log --ignore-working-copy -r 'trunk()' --no-graph -T 'bookmarks'))" >&2
fi
base_id=$(jjq log --ignore-working-copy -r "$base" --no-graph -T 'commit_id ++ "\n"' | head -1)
case "$base_id" in
""|0000000000000000000000000000000000000000) echo "error: base not found or resolves to root(): $base; pass -b <revset>" >&2; exit 1 ;;
esac

# PR state by branch, fetched once as [{number, state, head}] with a lowercase
# state. Origin when its CLI can read this repo's PRs, otherwise gh. Empty when
# neither can. Both run from the main repo, since workspaces have no .git.
prs=$(mktemp)
if command -v origin >/dev/null 2>&1 \
	&& raw=$(cd "$main_wt" && origin pr list --author "@me" --state all --limit 1000 \
		--json number,status,headRef 2>/dev/null); then
	printf '%s' "$raw" | jq '[.[] | {number, state: .status, head: .headRef}]' > "$prs" 2>/dev/null
elif raw=$(cd "$main_wt" && gh pr list --author "@me" --state all --limit 1000 \
	--json number,state,headRefName 2>/dev/null); then
	printf '%s' "$raw" | jq '[.[] | {number, state: (.state | ascii_downcase), head: .headRefName}]' > "$prs" 2>/dev/null
fi
[ -s "$prs" ] || echo "[]" > "$prs"

# Chats: Claude Code keeps ~/.claude/projects/<slug>/*.jsonl, slug = path with
# "/" and "." changed to "-". agy keeps ~/.gemini/antigravity-cli/brain/<id>/
# .system_generated/logs/transcript.jsonl, and conversation_summaries.db maps
# each chat to the folder it started in. A chat started in the main repo
# mentions the workspace path; a chat started in the workspace is found by its
# folder.
slugdir() { printf '%s/.claude/projects/%s' "$HOME" "$(printf '%s' "$1" | tr '/.' '--')"; }
if stat -c %Y / >/dev/null 2>&1; then mtimes() { xargs stat -c '%Y %n' 2>/dev/null; }
else mtimes() { xargs stat -f '%m %N' 2>/dev/null; }; fi
now=$(date +%s)

agy_db="${AGY_CONVERSATION_DB:-$HOME/.gemini/antigravity-cli/conversation_summaries.db}"
agy_brain="$(dirname "$agy_db")/brain"
agy_chats=$(mktemp)
if [ -f "$agy_db" ] && command -v python3 >/dev/null 2>&1; then
	python3 -c '
import json, os, sqlite3, sys, urllib.parse
# agy stores "2026-10-23 19:23:20.461873344+00:00"; SQLite parses it on any
# Python version, unlike datetime.fromisoformat before 3.11.
conn = sqlite3.connect("file:" + os.path.abspath(sys.argv[1]) + "?mode=ro", uri=True)
chats = {}
for uris, ts in conn.execute("SELECT workspace_uris, CAST(strftime(\"%s\", last_modified_time) AS INTEGER) FROM conversation_summaries"):
    try:
        uris = json.loads(uris)
    except ValueError:
        continue
    for uri in uris if isinstance(uris, list) else [uris]:
        if not isinstance(uri, str) or not uri or not ts:
            continue
        p = urllib.parse.unquote(urllib.parse.urlparse(uri).path) if uri.startswith("file://") else uri
        for k in {os.path.normpath(p), os.path.realpath(p)}:
            chats[k] = max(chats.get(k, 0), ts)
for path, ts in chats.items():
    print(f"{path}\t{ts}")
' "$agy_db" > "$agy_chats" || echo "warn: could not read $agy_db; agy chats started in a workspace are missed" >&2
elif [ -f "$agy_db" ]; then
	echo "warn: python3 not found; agy chats started in a workspace are missed" >&2
fi

# DSH keeps zstd-compressed transcripts under ~/.dsh/sessions/<slug>/<id>/
# session.v4.jsonl.zstd. Each one names the folder it started in, so a path
# match covers both cases. bun decompresses them in one pass (macOS has no zstd
# CLI) and prints "<workspace>\t<mtime>" for every workspace a transcript names.
dsh_sessions="${DSH_SESSIONS_DIR:-$HOME/.dsh/sessions}"
dsh_chats=$(mktemp)
if [ -d "$dsh_sessions" ] && command -v bun >/dev/null 2>&1; then
	printf '%s\n' "$workspaces" | cut -f2 | grep . | bun -e '
const fs = require("fs"), path = require("path");
const wts = fs.readFileSync(0, "utf8").split("\n").filter(Boolean).map((w) => w.replace(/\/$/, ""));
const files = fs.readdirSync(process.argv[1], { recursive: true })
  .filter((f) => f.endsWith("session.v4.jsonl.zstd")).map((f) => path.join(process.argv[1], f));
for (const f of files) {
  let text;
  try {
    text = Bun.zstdDecompressSync(fs.readFileSync(f)).toString();
  } catch (e) {
    console.error(`warn: could not decompress ${f}: ${e.message}`);
    continue;
  }
  const mtime = Math.floor(fs.statSync(f).mtimeMs / 1000);
  for (const wt of wts)
    if (["/", "\"", "\\", " "].some((t) => text.includes(wt + t))) console.log(`${wt}\t${mtime}`);
}
' "$dsh_sessions" > "$dsh_chats" || echo "warn: could not read DSH transcripts in $dsh_sessions" >&2
elif [ -d "$dsh_sessions" ]; then
	echo "warn: bun not found; DSH chats are missed" >&2
fi

echo "# base: $base"
printf "SIZE\tAGE\tMERGED\tDIRTY\tREMOTE\tPR\tLAST_CHAT\tBUCKET\tWORKTREE\n"

printf '%s\n' "$workspaces" | while IFS=$'\t' read -r name wt; do
	[ -z "$name" ] && continue
	# A workspace whose directory was deleted without a forget has no root.
	[ -z "$wt" ] && { printf "0\t?\t?\tmissing\t?\t-\t-\treview\t%s:(missing dir)\n" "$name"; continue; }
	[ "$wt" = "$main_wt" ] || [ "$wt" = "$repo" ] && continue

	size=$(du -sh "$wt" 2>/dev/null | awk '{print $1}'); [ -z "$size" ] && size=0

	# Uncommitted work is a non-empty @. jj tracks new files automatically, so
	# every change counts as wip. A failure (missing dir, stale working copy)
	# reads as unknown and holds, since it may hide work.
	if ! summary=$(jjq -R "$wt" diff --summary); then dirty=unknown
	elif [ -z "$summary" ]; then dirty=clean
	else dirty="wip:$(printf '%s\n' "$summary" | grep -c .)"; fi

	# The tip is @ when it carries work, else its parent @-.
	tip=$([ "$dirty" = clean ] && echo '@-' || echo '@')
	read -r head head_ts bm <<EOF
$(jjq -R "$wt" log --ignore-working-copy -r "$tip" --no-graph \
	-T 'commit_id ++ " " ++ committer.timestamp().format("%s") ++ " " ++ local_bookmarks.map(|b| b.name()).join(",") ++ "\n"')
EOF
	head_ts=${head_ts:-0}
	age=$([ "$head_ts" -gt 0 ] 2>/dev/null && echo "$(( (now - head_ts) / 86400 ))d" || echo "?")

	# Squash-merged branches are not ancestors of the base, so PR state is the
	# real signal; the ancestry check only catches fast-forward/rebase merges.
	[ -n "${head:-}" ] && [ -n "$(jjq log --ignore-working-copy -r "$head & ::($base)" --no-graph -T commit_id)" ] \
		&& merged=YES || merged=no

	branch=${bm%%,*}
	if [ -z "$branch" ]; then remote=no-bookmark
	elif rid=$(jjq log --ignore-working-copy -r "\"$branch\"@origin" --no-graph -T commit_id) && [ -n "$rid" ]; then
		[ "$rid" = "$head" ] \
			&& remote=pushed \
			|| remote="ahead$(jjq log --ignore-working-copy -r "\"$branch\"@origin..$head" --no-graph -T '"x\n"' | grep -c .)"
	else remote=no-remote; fi

	pr=$([ -n "$branch" ] && jq -r --arg b "$branch" \
		'.[] | select(.head==$b) | "#\(.number)/\(.state)"' "$prs" 2>/dev/null | head -1)
	[ -z "$pr" ] && pr="-"

	# Most recent chat that operated in this workspace, from every source: a
	# Claude, agy or DSH transcript that mentions the path, a Claude chat started
	# in it, or an agy chat started in it. Match path followed by "/", a quote,
	# the backslash of an escaped quote or a space so glint-482 does not match
	# glint-482-r37.
	last="-"; last_ts=$( {
		{ [ -d "$(slugdir "$main_wt")" ] && find "$(slugdir "$main_wt")" -maxdepth 1 -name '*.jsonl'
		  [ -d "$agy_brain" ] && find "$agy_brain" -path '*/.system_generated/logs/transcript.jsonl'
		} 2>/dev/null | xargs grep -lF -e "${wt}/" -e "${wt}\"" -e "${wt}\\" -e "${wt} " 2>/dev/null | mtimes
		[ -d "$(slugdir "$wt")" ] && find "$(slugdir "$wt")" -maxdepth 1 -name '*.jsonl' 2>/dev/null | mtimes
		real_wt=$(cd "$wt" 2>/dev/null && pwd -P)
		awk -F'\t' -v p="${wt%/}" -v r="$real_wt" '$1==p || $1==r {print $2}' "$agy_chats" "$dsh_chats"
	} | awk '{print $1}' | sort -rn | head -1)
	last_ts=${last_ts:-0}
	[ "$last_ts" -gt 0 ] && last=$(date -d "@$last_ts" '+%Y-%m-%d' 2>/dev/null || date -r "$last_ts" '+%Y-%m-%d' 2>/dev/null)
	recent=$([ "$last_ts" -gt 0 ] 2>/dev/null && [ $(( (now - last_ts) / 86400 )) -le 4 ] && echo yes || echo no)

	case "$dirty" in wip:*|unknown) bucket=hold-wip ;; *)
		case "$pr" in */open|*/draft) bucket=hold-open-pr ;; *)
			if [ "$recent" = yes ]; then bucket=verify-recent-chat
			elif [ "$merged" = YES ] || [ "$pr" != "-" ]; then bucket=safe
			else bucket=review; fi ;;
		esac ;;
	esac

	printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
		"$size" "$age" "$merged" "$dirty" "$remote" "$pr" "$last" "$bucket" "$name:$wt"
done | sort -t$'\t' -k1,1 -rh

rm -f "$prs" "$agy_chats" "$dsh_chats"
