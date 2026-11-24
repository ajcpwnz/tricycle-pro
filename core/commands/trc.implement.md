---
description: Implement a spec that passes the validator. Work its checklist, test, and ship.
model: opus
---

## User Input

```text
$ARGUMENTS
```


## Load the spec

Read `spec.store` and `spec.dir` from `tricycle.config.yml`. The input names the
spec: a path to a `.md` file, a ticket id or tracker URL, or a spec id under
`spec.dir`. Read a ticket with the tracker's MCP, including its comments.

In obsidian mode, read the note in `<spec.dir>` in the vault with the read tool of
the `obsidian` MCP server. In mcpvault, this tool is `read_note`. The note name
follows `spec.obsidian.note_name`. If the `obsidian` server is not connected, stop.
Tell the user to run `tricycle generate mcp`, set `OBSIDIAN_VAULT_PATH` and restart Claude Code.
Do not fall back to a repo file.
A missing `spec.obsidian` key takes its default: `note_name: id`, `frontmatter: none`, `done: stay`.

If no spec with `Analysis`, `Proposed Solution` and `Checklist` exists, stop and
tell the user to run `/trc.plan <input>` first.


## Validation gate

Read the status line of the spec.

- **`Status: validated @ <sha>`:** run `git diff --name-only <sha>`. If no file
  that the spec cites is in the output, the spec is current. Start, and do not
  run the validator.
- **Other status, or a cited file changed:** run the `trc-spec-validator` agent
  one time, with model `opus`. Give it the full spec text and the
  repository root.

On PASS, start. Add each new handoff to the `## Implementer Notes` section of the
spec.

In obsidian mode, write the handoffs with the patch tool of the `obsidian` server.
The `git diff` check does not see changes to the note itself. It sees only the
repo files that the spec cites.

On FAIL, do not start. Report the blockers and tell the user to run
`/trc.plan <input>`. Do not fix the spec here.


## Graphify Context

**Runtime gate — evaluate before acting on this block.** This block is
active for this turn if AND ONLY IF both conditions hold:

1. `tricycle.config.yml` has `integrations.graphify.enabled: true`.
2. `graphify-out/graph.json` exists at the repo root.

If either check fails, skip this entire section — it does not apply and
you MUST NOT attempt any graphify call. Continue with normal
grep/read/file-based exploration.

If both checks pass, a knowledge graph of this repo is available to
short-circuit the usual 'open files to find things' loop. Prefer
querying it BEFORE wide file reads:

- **GRAPH REPORT** (read once for orientation):
  `graphify-out/GRAPH_REPORT.md` — lists god nodes, surprising
  connections, and suggested questions.
- **LOCAL QUERY** (cheap, no MCP needed):
  - `graphify query "<your question>"` — BFS traversal for a question.
  - `graphify explain "<symbol-or-concept>"` — plain-language expansion
    of a node and its neighbors.
  - `graphify path "<A>" "<B>"` — shortest path between two concepts.
- **RAW JSON**: `graphify-out/graph.json` when you need every edge.
- **MCP** (only if `.mcp.json` has a `graphify` entry AND it was
  registered before this `claude` session started): tools
  `{query_graph, get_node, get_neighbors, get_community, god_nodes,
  graph_stats, shortest_path}`. Claude Code does not load `.mcp.json`
  edits mid-session. Do not assume that these tools exist. Call one to
  probe them, and use the shell CLI above if the call fails.

**WHEN to query**: architectural questions, such as where X is defined,
who calls Y, or what depends on Z. Also query before you grep for a
location, and to find a helper that already exists. Every edge carries a provenance
tag — EXTRACTED (found directly), INFERRED (reasonable guess with
confidence), AMBIGUOUS (flagged). Treat INFERRED as a hint, not truth.

**WHEN NOT to query**: trivial one-file edits, cosmetic fixes, anything
where you already know the exact file path. The graph is a shortcut,
not a mandatory gate.

**STALENESS**: the graph is refreshed automatically by the kickoff
hook before you started. If you touch code and then need to re-query
the updated state, run `graphify . --update` yourself — do NOT trust
stale nodes after you've mutated the tree.


## Work the checklist

1. Re-read the code the spec names. If it no longer matches the analysis, stop
   and send the user to `/trc.plan`.
2. Resolve each item of `## Implementer Notes` in the spec: read the code it
   names, decide, and do it as part of the item it touches. A note that turns
   out to break the feature as specified: stop and send the user to `/trc.plan`.
3. Work the checklist items in order. Write a failing test first wherever the
   project has tests for that area.
4. **Delegate to keep this context slim.** Hand an item to a worker subagent
   (Agent tool, model `opus`) when its work is self-contained. A
   self-contained item touches its own files and needs no decision from this
   session. Give the worker the spec, the one item, the files and its proof. Ask
   for the diff summary and the evidence back, not file dumps. Keep in this session the items
   that cut across others or need a judgment call. Workers on different items run
   in parallel only when their files do not overlap.
5. An item is done only when its proof is observed: the command ran and printed
   the expected result, or the behavior was seen. A worker's report is a claim:
   check its diff and re-run its proof here before you mark the item. Then mark it
   `[x]` in the spec (the file in repo mode, the ticket description in linear
   mode, the note in obsidian mode) with a short note of the evidence.
   Patch the note with the `obsidian` server.
6. Do not stop with an open item unless it needs something only the user holds.
   In that case, name it and ask.
7. Work the spec names nothing about is out of scope. Mention it, do not do it.


## Lint and test

For every app the change touches, run its `lint` and `test` commands from `apps`
in `tricycle.config.yml`. Run long suites through a worker subagent (Agent tool,
model `opus`) that returns the exit codes and only the failing
output. A failure is a bug to fix, then run again. Never skip, disable or weaken a
test to get green.


## Version bump

After every checklist item is done and tests pass, before reporting completion:
    - Read the current version from the `VERSION` file in the repo root
    - Bump the patch version, for example `0.2.0` → `0.2.1`. For a new feature, bump the minor version: `0.2.0` → `0.3.0`.
    - Write the new version to `VERSION`
    - Include the version bump in the final commit (do NOT create a separate commit for it)


## Push, PR & Deploy

After every checklist item is done and tests pass (and the version-bump block, when enabled, has run), execute the push/PR/merge workflow:

### 0. Local testing gate

**MANDATORY.** Do this step only if this command contains the Local Stack Testing section (the `test-local-stack` block). Before you show a summary or ask to push, make sure that the browser evidence is on disk:

1. Get the current branch: `git rev-parse --abbrev-ref HEAD`.
2. Make sure that all of these conditions are true:
   - The file `specs/<branch>/.local-testing-passed` exists and is not empty.
   - There is a minimum of one browser screenshot in `specs/<branch>/local-testing/`, or the first line of the marker is `USER-APPROVED SKIP:`.
3. **If a condition is false**: stop. Do not show a summary. Do not ask to push. Go back to Local Stack Testing, do the browser test, save the screenshots, and write the marker.
4. **If all conditions are true**: go to step 1.

Do not skip this step. Do not give yourself an exemption. Only a `USER-APPROVED SKIP:` first line, which the user approved in this session, replaces the screenshots.

### 1. Read push configuration

Read `tricycle.config.yml` and extract:
- `push.require_approval` (boolean, default true)
- `push.pr_target` (string, default "main")
- `push.merge_strategy` (string: squash, merge, or rebase)
- `push.auto_merge` (boolean, default false)

### 2. Summarize changes

Present a summary to the user:
- What was implemented (the spec title and its checklist)
- Files changed (count and key files)
- Tests passed (which test suites ran and their results)
- Version bumped (old → new)

### 3. Push approval gate

**If `push.require_approval` is true** (default):
1. State that you are ready to push and present the summary.
2. **Stop and wait** for the user to say "push", "go ahead", or equivalent.
3. Each push requires **fresh approval**. Earlier approval does not carry over.
4. If the user declines or says "stop", "wait", "no" — do NOT push. Do NOT create a PR. Stop the workflow.

**If `push.require_approval` is false**: Proceed directly to step 4.

### 4. Push and create PR

1. Push the branch to the remote with the `-u` flag.
2. Create a PR targeting `push.pr_target` using `gh pr create`.
3. Include the change summary in the PR body.

**If push fails** (remote rejected, auth error, network failure): Report the error clearly and stop. Do not retry.

### 5. Merge (if auto_merge is true)

**If `push.auto_merge` is true**:
1. Check for merge conflicts with `gh pr view <pr-number> --json mergeable,mergeStateStatus`.
   - If `mergeable` is `UNKNOWN`, GitHub has not calculated it yet. Wait 10 seconds and check again.
   - If `mergeable` is `CONFLICTING`, repair the conflicts. Do not stop:
     a. Rebase onto the target branch: `git fetch origin && git rebase origin/<pr_target>`.
     b. For each file that has a conflict, read the two sides, decide the result, write it, and `git add` the file.
     c. Continue the rebase: `git rebase --continue`.
     d. Push the rebased branch: `git push --force-with-lease`.
     e. Check `mergeable` again. If the conflicts continue after the rebase, report them and stop. The user must repair them.
   - If `mergeable` is `MERGEABLE`, merge the PR.
   - Do not force-merge.
2. Merge using the configured `push.merge_strategy` via `gh pr merge`.
3. If merge is blocked (branch protection, required reviewers), report the blocker and wait.

**If `push.auto_merge` is false**: Report the PR URL and let the user handle merging.

### 5b. Delete blocking relations (after a checked merge)

After a successful merge, find the ticket. Use the spec Source line if it has a ticket id. This also applies in obsidian mode. If `spec.store` is `linear`, use the ticket that holds the spec. If there is no ticket, skip this step.

1. Use the tracker MCP to get the ticket relations, and find the tickets that it blocks.
2. Delete all of these blocking relations, so that the work that follows is not blocked. In Linear, use the `removeBlocks` field.

### 6. Artifact cleanup (only after a checked merge)

**IMPORTANT**: Do NOT clean up artifacts until the PR is successfully merged. If merge has not happened, skip this step entirely.

After you check that the merge happened:
1. Delete the scratch directory `specs/{branch}/` (local testing evidence), if it exists. The spec itself stays: in repo mode it is committed under `spec.dir`. In obsidian mode it stays in the vault and is not part of the commit. With `spec.obsidian.done: move`, move the note to `<spec.dir>/done` with the `obsidian` server.
2. If in a worktree (`.git` is a file), note that the worktree-cleanup block (if active) handles worktree removal separately.
3. If NOT in a worktree, switch back to the base branch and delete the feature branch locally.

### 7. Error handling

On **any failure** during this workflow (push rejected, PR creation failed, merge blocked, conflicts):
- Report the error clearly with context.
- Stop the workflow. Do not continue to the next step.
- Do not retry automatically.
- Do not clean up artifacts.
- Suggest what the user can do to resolve the issue.

