---
name: graphify-context
step: tasks
description: Brief the agent on the graphify knowledge graph (runtime conditional; opt-out via integrations.graphify.enabled=false)
required: false
default_enabled: true
order: 25
---

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
  graph_stats, shortest_path}`. Mid-session `.mcp.json` edits do NOT
  hot-load, so do not assume these tools exist — probe by calling one
  and fall back to the shell CLI above on failure.

**WHEN to query**: architectural questions (where is X defined, who
calls Y, what depends on Z), code-location lookups before grepping,
"is there already a util for this?". Every edge carries a provenance
tag — EXTRACTED (found directly), INFERRED (reasonable guess with
confidence), AMBIGUOUS (flagged). Treat INFERRED as a hint, not truth.

**WHEN NOT to query**: trivial one-file edits, cosmetic fixes, anything
where you already know the exact file path. The graph is a shortcut,
not a mandatory gate.

**STALENESS**: the graph is refreshed automatically by the kickoff
hook before you started. If you touch code and then need to re-query
the updated state, run `graphify . --update` yourself — do NOT trust
stale nodes after you've mutated the tree.
