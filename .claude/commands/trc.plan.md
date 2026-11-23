---
description: Write or revalidate a spec (analysis, proposed solution, checklist) for a request, ticket or spec file.
model: fable
---

## User Input

```text
$ARGUMENTS
```


## Resolve the input

Read `spec.store` (`repo` or `linear`, default `repo`) and `spec.dir` (default
`docs/specs`) from `tricycle.config.yml`.

Classify the user input:

| Input | Source |
|-------|--------|
| Path to a `.md` file | that file |
| Ticket id or tracker URL | the ticket, read with the tracker's MCP (`get_issue`), including its comments |
| Anything else | a new request in plain text |

The input is an **existing spec** when its text already has the sections
`Analysis`, `Proposed Solution` and `Checklist`. In repo mode, a ticket id whose
file `<spec.dir>/<TICKET-ID>.md` exists is an existing spec too.

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

Fill `.trc/templates/spec-template.md`. Keep it compact: one spec, three parts.

- **Analysis:** the problem, the current behavior with `path:line` references, the
  constraints, and what is out of scope.
- **Proposed Solution:** the approach, each decision with the alternative it beat,
  and the risks.
- **Checklist:** one line per outcome, each naming its proof. An outcome is
  something a reviewer can observe ("the export endpoint returns 403 for a viewer").
  An edit instruction ("change line 40") is not an outcome.
- **Open Questions:** must be empty before the spec can pass.

Set `Source:` to the ticket id, URL or a one-line summary of the request.


## Validation

Run the `trc-spec-validator` agent with model `opus`. Give it the
full spec text and the repository root, nothing else: no summary of your own
reasoning.

- **PASS:** set `Status: validated` and go to the store section.
- **FAIL:** fix each finding.
  - Truthfulness and quality findings: fix the spec from the code.
  - Ambiguity findings that only the user can settle: ask with `AskUserQuestion`,
    then write the answer into the spec.

  Then run a fresh validator again. After three failed rounds, stop: keep
  `Status: draft`, store the spec, and report the remaining findings.

An existing spec goes through the same loop. Change only what a finding names.


## Store

- **`spec.store: repo`:** write `<spec.dir>/<spec id>.md`. If a ticket exists, add
  a comment on it linking the file.
- **`spec.store: linear`:** the spec becomes the ticket description. For new work
  from a ticket, keep the original request below the spec under
  `## Original Request`. For a request with no ticket, create one with the tracker's
  MCP.

Report the spec location, its status, and the validator verdict. Do not start
implementation: that is `/trc.implement <spec id>`.

