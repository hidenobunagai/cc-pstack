# pstack in Claude Code

pstack skills use Cursor names. In Claude Code, read this file once per session, then map each Cursor name in a skill with the tables below. `<pstack>` means the folder that holds `skills/` and `docs/`. If a Cursor field has no row, drop it and say so. Never pass a field or value the tool schema rejects.

## Tools

| Cursor | Claude Code |
| --- | --- |
| `Task` | `Agent` |
| `AskQuestion` | `AskUserQuestion`. In `-p` mode it is absent, so ask in plain text. |
| Open a todolist | Use `TodoWrite` if the session offers it. Otherwise keep the list in your reply and update it at each phase. |
| Run another pstack skill (`/name` or "the **name** skill") | `Read` `<pstack>/skills/<name>/SKILL.md` and follow it. The `Skill` tool refuses most pstack skills. When you tell the user to type it, write `/pstack:<name>`. |
| `Grep`, `Glob` | `Bash` with `rg` when the session has no `Grep` or `Glob`. |

## Subagent fields

| Cursor | Claude Code |
| --- | --- |
| `subagent_type: generalPurpose` | `subagent_type: "general-purpose"` |
| `poteto-agent`, `comment-sicko` | `pstack:poteto-agent`, `pstack:comment-sicko` |
| `readonly: true` | `subagent_type: "Explore"`. It keeps `Bash`, so the brief also says "do not edit files", and you check `jj st` afterward. |
| `readonly: false` | `general-purpose`. It keeps the session's MCP servers. |
| `environment: "cloud"` | Never pass `isolation: "worktree"` and never call `EnterWorktree`: both create git worktrees, and this host runs jj only. Before spawning, run `jj workspace add <path> -r <base>` yourself (one workspace per writing worker), put the path in the brief, and tell the worker to work only there, finish with `jj commit -m`, and report with `jj diff`. A workspace has no `.git`, so the worker runs `gh` from the main repo. When the worker needs its own machine, use `create_session` with `source_url`, `source_revision`, and `outcome_branch` instead. |
| `environment: "local"` | Omit. |
| `cloud_base_branch: <b>` | Pass `-r <b>@origin` to `jj workspace add` after `jj git fetch`, or `source_revision: <b>` to `create_session`. |
| `run_in_background: true` | Omit. Subagents run in the background by default and notify you when they finish. |
| `resume` | Spawn a new agent and paste the earlier result into its brief. |
| `file_attachments` | List the paths in the brief. |

## Models

| Cursor | Claude Code |
| --- | --- |
| `claude-<family>-<version>-<effort>[-fast]`, such as `claude-opus-5-5-xhigh` | `model: "opus"` and `effort: "xhigh"`. `model` takes only `opus`, `sonnet`, `haiku`, `fable`. Drop `-fast`. |
| A `grok-*`, `gpt-*`, or other non-Claude slug | `model: "sonnet"` with the slug's effort, and say so. Panels keep two model families this way. |
| `auto` or `inherit-parent` | `model: "opus"`. |
| An omitted `model` | Never omit `model` on an `Agent` call. This host sets `CLAUDE_CODE_SUBAGENT_MODEL=haiku`, so an omitted model runs on haiku, not the session model. An explicit `model` overrides the variable. The same holds for `agent()` calls in a Workflow script: pass `model` in its options. |
| The `pstack-models.mdc` rule, `~/.cursor/rules/pstack-models.mdc` | `~/.claude/rules/pstack-models.md`. Claude Code loads it into every new session, so its role lines are already in context. If they are not, read the file. If the file or the role's line is missing, use the skill's default slug. |
| A role value `<model> <effort>`, such as `opus high` | `model: "opus"` and `effort: "high"`. |

## setup-pstack

Claude Code loads every `.md` file in `~/.claude/rules/` into each new session, so `setup-pstack` writes its rule there. Follow its steps with these changes:

- Detect. The detected models are the `model` values that the `Agent` tool schema lists, each with an effort from its `effort` values. Write a real model as `<model> <effort>`, such as `opus xhigh`. The effort is the last token, so the budget step works as written.
- Defaults. Map each default slug with the rows above: `claude-opus-5-5-xhigh` is `opus xhigh`, and `grok-4.7-xhigh-fast` is `sonnet xhigh`. Never write `inherit-parent` or `auto`; they mean `opus` here (see Models).
- Write. Write `~/.claude/rules/pstack-models.md` with no frontmatter, then the comment lines, the `# budget` line, and one line per role from step 5. Overwrite the whole file. Never put the role lines in `CLAUDE.md` or `AGENTS.md`.

## Paths

| Cursor | Claude Code |
| --- | --- |
| `.cursor/skills/`, `~/.cursor/skills/` | `.claude/skills/`, `~/.claude/skills/` |
| `~/.cursor/plugins/`, `.cursor-plugin/plugin.json` | `~/.claude/plugins/`, `.claude-plugin/plugin.json` |
| `.cursor/rules/*.mdc`, always-applied rules | `CLAUDE.md`, or `AGENTS.md` when no `CLAUDE.md` exists. Claude Code never reads `.mdc` files. The model rule is the exception. See Models. |
| `https://github.com/cursor/plugins/blob/main/pstack/<path>` | `<pstack>/<path>` when that file exists. The plugin ships the skills, `docs/guide/`, and `README.md`. Read the local copy and never fetch it. Give the user the URL when they need a link. |
| Transcripts in `~/.cursor/projects/<slug>/agent-transcripts/` | `~/.claude/projects/<slug>/<session>.jsonl`. The slug is the workspace path with each `/` and `.` changed to `-`, so `/Users/you/proj` is `-Users-you-proj`. The newest `.jsonl` directly in that folder is the current session. Its `<session>/subagents/` folder holds subagent transcripts. Read only this workspace's folder. |

## Version control

Every repo on this host is a colocated jj repo, and git HEAD is detached there by design. Map each git step in a skill to jj. Never run a git write command (`add`, `commit`, `checkout`, `switch`, `branch`, `stash`, `rebase`, `reset`, `worktree`, `push`). Read-only `git` (`log`, `show`, `diff`, `merge-tree`, `remote get-url`) and `gh` are fine in the main repo.

| Cursor (git) | Claude Code (jj) |
| --- | --- |
| `git worktree add <path> <b>` | `jj workspace add <path> -r <b>` |
| `git worktree remove --force <path>`, `git worktree prune` | `jj workspace forget <name>` from the main repo, then `rm -rf <path>`, then `jj workspace list` to confirm. `jj undo` restores a forget. |
| `git fetch && git reset --hard origin/<b>` | `jj git fetch` then `jj new <b>@origin` |
| `git checkout <sha>` | `jj new <sha>`, or `jj edit <sha>` to change that commit itself |
| `git add <files> && git commit -m` | `jj commit <files> -m "..."`, with explicit paths when the skill says not to stage everything |
| amend | `jj squash` (into `@-`) or `jj squash --into <change>` |
| `git rebase` onto trunk, reorder a stack | `jj git fetch` then `jj rebase -d 'trunk()'`; reorder with `jj rebase -s <change> -d <parent>`. Descendants follow. |
| split a commit | `jj split <files>` |
| `git push`, `git push --force-with-lease` | `jj bookmark set <name> -r @-` then `jj git push -b <name>`. After a rebase, move every bookmark in the stack and push them together (`jj git push -b <a> -b <b>`). Ask the user before moving a bookmark someone else pushed to. |
| `gh pr create` | Push the bookmark first, then `gh pr create --head <name> --base <parent-or-trunk>`. gh cannot infer the branch from a detached HEAD. |
| `git diff <base>...HEAD`, `git diff main...HEAD` | `jj diff -r '<base>..@'`, base as a revset such as `trunk()` or `<b>@origin`. This matches the merge-base diff; `--from <base>` would also show trunk's newer changes reversed. `git diff` against HEAD misses the working-copy change `@`. |
| `git diff` (working tree), `git status` | `jj diff`, `jj st` |
| `git log <base>..HEAD` | `jj log -r '<base>..@'` |
| `git show origin/<b>:<path>` | `jj file show -r <b>@origin <path>` |
| current branch | `jj log -r @- --no-graph -T 'bookmarks'` |

## Local equivalents

These tools exist in this Claude Code setup. Use them where a skill names the Cursor tool.

| Cursor | Claude Code |
| --- | --- |
| `control-ui`, browser verification | The `web-verify` skill (screenshots, console and network errors). A recorded flow is `web-demo-video`. |
| `control-cli`, launching the app | The `run` skill, then `Bash` against the real binary. |
| Native mobile or desktop control | Skip with the line below. |
| `/deslop` on code | The `simplify` skill. |
| `/deslop` on prose | The `unslop` skill for English. For Japanese prose, the `yomiyasu` skill. |
| `/create-skill` | The `anthropic-skills:skill-creator` skill. |
| Bugbot review pass | The `code-review` skill. A security pass is `security-review`. Bugbot comments already on a PR are ordinary review threads; triage them with `gh`. |
| Watching a PR for CI and review events | `subscribe_pr_activity`; events arrive as turns. `gh pr checks` and `gh pr view` for a one-shot look. |
| `/loop <interval> <prompt>` | The `loop` skill with the same arguments. Omit the interval to self-pace. |
| Automations routine on a schedule | The `schedule` skill or `create_trigger`. |
| Routine wake, a check later | `send_later`. |
| Automations webhook | `watch_url`. |
| Cursor cloud agent | `create_session`; status with `get_session`, output with `list_events`. |
| Past sessions and decisions (`recall`, `why`) | Search the shared memmini memory first with `memory_smart_search`, using the user's wording, then read transcripts. |

## Host

This Claude Code runs on Linux (Debian, arm64) and on macOS.

| Cursor | Claude Code |
| --- | --- |
| `npm`, `npx`, `pnpm`, `yarn` | `bun`, `bunx`. Package installs go through `pmg` (bare `bun add` and `bunx` are already shimmed). |
| `node <script>` | `bun <script>` |
| `pip`, `python` | `uv run`, `uv add` |
| `stat -f`, `date -r <epoch>` | On Linux, `stat -c '%Y %n'` and `date -d @<epoch>`. |
| macOS-only tools (`xcrun`, `simctl`, `sips`, `open`, `pbcopy`, `brew`, `launchctl`) | Check `uname` first. On Linux, skip with the line below. |
| Commit messages, PR text, code comments | English. Replies to the user follow the session language. |

## Cursor-only features

Most Cursor-only features have a local equivalent above. When a step needs one that has none, put one line in your reply, `Skipped in Claude Code: <step>. <reason>.`, then go on to the next step. Do not stop, ask, or retry. When a later step needs what the skipped step made, such as a URL or a key, leave a placeholder and name it in the line.

| Cursor | Claude Code |
| --- | --- |
| Cursor Automations `update_state` routine calls and `SendToUser` secret requests | Skip with the line. Schedules, wakes, and webhooks map through Local equivalents. |
| Bugbot | Bugbot comments on a GitHub PR are ordinary review threads, so triage them with the forge command that the step gives. Skip a step that starts, waits for, or configures Bugbot when the PR has no Bugbot check or comment. |
| Cursor cloud agents | See Subagent fields and Local equivalents. Skip only a step that needs Cursor's dashboard. |
| A built-in PR tool | Use the forge command that the step gives, such as `gh pr create`. That is not a skip, so write no line. |
