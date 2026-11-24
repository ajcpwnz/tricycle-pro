---
name: execute
step: implement
description: Work the spec checklist to the end, proving each item, with workers keeping the context slim
required: true
default_enabled: true
order: 30
---

## Work the checklist

1. Re-read the code the spec names. If it no longer matches the analysis, stop
   and send the user to `/trc.plan`.
2. Resolve each item of `## Implementer Notes` in the spec: read the code it
   names, decide, and do it as part of the item it touches. A note that turns
   out to break the feature as specified: stop and send the user to `/trc.plan`.
3. Work the checklist items in order. Write a failing test first wherever the
   project has tests for that area.
4. **Delegate to keep this context slim.** Hand an item to a worker subagent
   (Agent tool, model `{{models.workers}}`) when its work is self-contained. A
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
