---
description: Write or revalidate a spec (analysis, proposed solution, checklist) for a request, ticket or spec file.
model: fable
---

## User Input

```text
$ARGUMENTS
```


## Store setup

Do this step first. Ask fixed questions with `AskUserQuestion`, in the order
below, with the options below. Write each answer to `tricycle.config.yml` at once.
Do not ask a question again when its key is already in `tricycle.config.yml`.

1. **Store.** Ask only when an `obsidian` MCP server is connected and the config has no `spec.store` key.
   The options are `repo`, `linear` and `obsidian`. Write the answer to `spec.store`.
2. **Vault layout.** Ask these four questions as one group. Ask them only when
   `spec.store` is `obsidian` and the config has no `spec.obsidian` block.
   - Vault folder for the specs, relative to the vault root. The current
     `spec.dir` is one option. Write the answer to `spec.dir`.
   - `spec.obsidian.note_name`: `id` gives `<id>.md`. `id-title` gives `<id> <title>.md`.
   - `spec.obsidian.frontmatter`: `none` writes no frontmatter. `properties`
     writes `status`, `source` and `tags: [spec]`.
   - `spec.obsidian.done`: `stay` keeps the note in `spec.dir` after merge.
     `move` moves it to `<spec.dir>/done`.

Write the answers in this form. Keep the other keys under `spec`.

```yaml
spec:
  store: obsidian
  dir: <vault folder>
  obsidian:
    note_name: id        # id | id-title
    frontmatter: none    # none | properties
    done: stay           # stay | move
```

If no question is due, go to the next section.

An unattended run does not ask. In a `/trc.chain` or `/trc.band` worker, if a
question is due, stop and report the question.


## Resolve the input

Read `spec.store` (`repo`, `linear` or `obsidian`, default `repo`) and `spec.dir`
(default `docs/specs`) from `tricycle.config.yml`.

In obsidian mode, the spec is a note in the vault, and `spec.dir` is relative to
the vault root. Read, write and patch the note with the tools of the `obsidian` MCP
server. In mcpvault, these tools are `read_note`, `write_note` and `patch_note`.
If the `obsidian` server is not connected, stop. Tell the user to run
`tricycle generate mcp`, set `OBSIDIAN_VAULT_PATH` and restart Claude Code.
Do not fall back to a repo file.

Classify the user input:

| Input | Source |
|-------|--------|
| Path to a `.md` file | that file |
| Ticket id or tracker URL | the ticket, read with the tracker's MCP (`get_issue`), including its comments |
| Anything else | a new request in plain text |

The input is an **existing spec** when its text already has the sections
`Analysis`, `Proposed Solution` and `Checklist`. In repo mode, a ticket id whose
file `<spec.dir>/<TICKET-ID>.md` exists is an existing spec too. In obsidian mode,
a spec id with a note in `<spec.dir>` in the vault is an existing spec too. The
note name follows `spec.obsidian.note_name`.

- **Existing spec:** do not rewrite it. Skip to the validation section, then the
  store section. Fix only what validation finds.
- **New work:** continue with every section in order.

The spec id is the ticket id when there is one. Otherwise it is a short kebab-case
slug of the request.


## Plan mode

For new work, call the `EnterPlanMode` tool before any research, unless the work is
trivial: one file, no design choice, no new behavior. Plan mode is read-only. The
drafted spec is the plan: present it with `ExitPlanMode`, and store it only after
the user approves.


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


## Research

1. Read the project rules that bound the change: root `CLAUDE.md`, the
   constitution (`constitution.root` in `tricycle.config.yml`), and the rules file
   of every app the change touches.
2. Read the code the request touches. Find the cause, not only the symptom.
3. Record every fact with a `path:line` reference. A claim with no reference does
   not go into the spec.
4. Settle every choice you can from the code and the rules. A choice only the user
   can make goes to the user now, with `AskUserQuestion`, before the spec is written.


## Write the spec

Fill `.trc/templates/spec-template.md`. Keep it compact: the spec says what to
build and why, not each edit. The implementer reads the code and makes the small
choices.

- **Analysis:** the problem, the current behavior with `path:line` references to
  source files, the constraints, and what is out of scope.
- **Proposed Solution:** the approach, each decision with the alternative it beat,
  and the risks.
- **Checklist:** one line per outcome, each naming its proof. An outcome is
  something a reviewer can observe ("the export endpoint returns 403 for a viewer").
  An edit instruction ("change line 40") is not an outcome.
- **Open Questions:** must be empty before the spec can pass.
- **Implementer Notes:** leave empty. Validation fills it.

Set `Source:` to the ticket id, URL or a one-line summary of the request.

### Check the draft

Read `.trc/templates/spec-rubric.md`. The validator uses the same rubric. Do its
writer checks on the draft, with tools, and keep the draft in its size limit.


## Validation

Run the `trc-spec-validator` agent with model `opus`. Give it the
full spec text and the repository root, nothing else: no summary of your own
reasoning.

- **PASS:** copy each handoff, as the validator wrote it, into the
  `## Implementer Notes` section of the spec. Do not fix handoffs here and do not
  run the validator again.
- **FAIL:** fix each blocker from the code. A blocker that only the user can
  settle: ask with `AskUserQuestion`, then write the answer into the spec. Then
  run the validator again on the full spec, to test the fix. After three rounds
  that fail, stop and show the user the blockers.

Then set the status to `Status: validated @ <sha>`. The `<sha>` is the output of
`git rev-parse --short HEAD`. Go to the store section.

An existing spec goes through the same validation. Change only what a blocker
names.

In obsidian mode, write the Implementer Notes and the `Status:` line with the
patch tool of the `obsidian` server. With `spec.obsidian.frontmatter: properties`,
set the `status` property to the same value.


## Store

- **`spec.store: repo`:** write `<spec.dir>/<spec id>.md`. If a ticket exists, add
  a comment on it linking the file.
- **`spec.store: linear`:** the spec becomes the ticket description. For new work
  from a ticket, keep the original request below the spec under
  `## Original Request`. For a request with no ticket, create one with the tracker's
  MCP.
- **`spec.store: obsidian`:** write the note in `<spec.dir>` in the vault with the
  write tool of the `obsidian` server. The note name follows
  `spec.obsidian.note_name`: `id` gives `<spec id>.md`, and `id-title` gives
  `<spec id> <title>.md`. With `spec.obsidian.frontmatter: properties`, start the
  note with the properties `status`, `source` and `tags: [spec]`. With `none`,
  write no frontmatter. If a ticket exists, add a comment on it with the
  vault-relative path of the note. Do not create a ticket.

Report the spec location, its status, and the validator verdict. Do not start
implementation: that is `/trc.implement <spec id>`.

