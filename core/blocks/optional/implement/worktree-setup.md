---
name: worktree-setup
step: implement
description: Do the work in a git worktree (enabled by worktree.enabled)
required: false
default_enabled: false
order: 20
---

## Worktree

If `.git` is a file, you are already in a worktree: continue there.

Otherwise create one for this spec. Read `branching.style` (default `ordered`) and
`branching.prefix` from `tricycle.config.yml`, and pass them on:

```bash
.trc/scripts/bash/create-new-feature.sh --json --provision-worktree \
  --style "<branching.style>" --prefix "<branching.prefix>" \
  --issue "<ticket id, if any>" --short-name "<spec id>" "<spec title>"
```

The script creates the branch and the worktree, installs dependencies, runs
`worktree.setup_script` and checks `worktree.env_copy`. On a non-zero exit, report
its error verbatim and stop. Then `cd` into `WORKTREE_PATH` from its JSON output and
do all further work there.
