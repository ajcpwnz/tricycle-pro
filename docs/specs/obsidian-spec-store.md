# Specs can live in an Obsidian vault, through an MCP server

Source: request "add support for spec store obsidian, and of course use mcp", and a one-time setup step that asks the store and the vault layout · Status: validated @ d05682a

## Analysis

- **Problem:** a project cannot keep its specs in an Obsidian vault. `/trc.plan` and `/trc.implement` know only the repo and the tracker.
- **Current behavior:**
  - The plan blocks know two stores: `core/blocks/plan/resolve-input.md:12` and `core/blocks/plan/store-spec.md:13-18`.
  - The implement blocks read and update the spec in the file or the ticket: `core/blocks/implement/load-spec.md:12-14`, `core/blocks/implement/execute.md` (the `[x]` step) and `core/blocks/implement/push-deploy.md:91` (where the spec stays after merge).
  - `core/commands/trc.chain.md:509` and `core/commands/trc.band.md:144,526` give the spec location as a repo file or the ticket.
  - `bin/lib/status.sh:19-23` prints "Specs live in the tracker" for every store that is not `repo`.
  - `cmd_generate_mcp` (`bin/tricycle:732-826`) builds `.mcp.json` from `mcp.preset` and `mcp.custom.*` only. Custom servers are found by a grep on `CONFIG_DATA` at `bin/tricycle:746`.
  - `README.md:51-58` documents the store values.
- **Constraints:** `bash tests/run-tests.sh` passes (`CLAUDE.md`). Generated files are regenerated, not edited: `core/commands/trc.{plan,implement}.md` by `core/scripts/bash/assemble-commands.sh`, `.claude/` and `.trc/` by `tricycle dogfood --yes`. No personal vault path in the committed `tricycle.config.yml`.
- **Out of scope:** reading the vault from bash (`tricycle status` does not list vault specs), linting notes with the style gate, migration between stores.

## Proposed Solution

- **Approach:** a third store value, `obsidian`. The spec is the note `<spec.dir>/<spec id>.md`, with `spec.dir` relative to the vault root. The blocks read, write and patch the note with the tools of the MCP server registered as `obsidian`. If that server is not connected, the command stops and tells the user to run `tricycle generate mcp`, set `OBSIDIAN_VAULT_PATH` and restart Claude Code.
  - `tricycle generate mcp`: when `spec.store` is `obsidian` and there is no `mcp.custom.obsidian`, add `"obsidian": {"command": "npx", "args": ["-y", "@bitbonsai/mcpvault@latest", "${OBSIDIAN_VAULT_PATH}"]}` through the existing custom-server merge.
  - `store-spec`: write the note. If a ticket exists, comment on it with the vault-relative path. `execute`: mark `[x]` in the note. `push-deploy`: the spec stays in the vault and is not committed.
  - `status.sh`: a separate line for `obsidian` that names the vault.
  - A new block, `setup-store`, runs first in `/trc.plan` and `/trc.implement`. It asks fixed questions with `AskUserQuestion`, in a fixed order, with fixed options. It writes each answer to `tricycle.config.yml`. A question whose key is already in the config is not asked again.
    - Store question: asked only when an `obsidian` MCP server is connected and the config has no `spec.store` key. Options: `repo`, `linear`, `obsidian`.
    - Layout questions: asked only when `spec.store` is `obsidian` and the config has no `spec.obsidian` block. They set `spec.dir` (vault folder), `spec.obsidian.note_name` (`id` gives `<id>.md`, `id-title` gives `<id> <title>.md`), `spec.obsidian.frontmatter` (`none`, or `properties` for `status`, `source` and `tags: [spec]`) and `spec.obsidian.done` (`stay`, or `move` to `<spec.dir>/done` after merge).
  - The obsidian text in `store-spec`, `load-spec`, `execute` and `push-deploy` follows these keys.
  - The chain and band text, and the README (values, the env var, the Node.js v22.12.0 minimum of `mcpvault`, the restart, the override).
- **Decisions:**
  - MCP, not direct file access: the user chose it. Direct access needs a vault path in the commands and permission outside the repo.
  - `mcpvault`, not `mcp-obsidian`: it works on the files, so unattended `/trc.chain` and `/trc.band` workers do not need the Obsidian app open.
  - `${OBSIDIAN_VAULT_PATH}`, not a config key: nothing personal is committed.
  - `mcp.custom.obsidian` wins over the default: any Obsidian server works with no new key.
  - Stop when the server is absent, not fall back to the repo: a fallback puts specs in two places.
  - Ask once and save the answers in the config, not ask per ticket: the user asked for this. The questions live in one block, so each run asks the same questions in the same order.
  - Ask the store question only when an `obsidian` server is connected, not whenever `spec.store` is absent: repos without Obsidian keep the `repo` default with no question.
- **Risks:** the injected entry breaks `.mcp.json` next to a preset or other custom servers (tests parse each case). Other servers have other tool names: the blocks name the role.

## Checklist

- [x] `tricycle generate mcp` with `spec.store: obsidian` writes valid JSON with the `obsidian` server next to the preset and other custom servers — verify: new tests in `tests/run-tests.sh`. Done: the 7 new generate-mcp tests in `tests/run-tests.sh` pass.
- [x] `mcp.custom.obsidian` replaces the default, and `spec.store: repo` adds no `obsidian` server — verify: new tests in `tests/run-tests.sh`. Done: the override and repo tests in `tests/run-tests.sh` pass.
- [x] `tricycle status` with `spec.store: obsidian` names the Obsidian vault, and the `linear` text does not change — verify: new test in `tests/run-tests.sh`, and the existing `linear` test passes. Done: the obsidian status test and the exact linear-line test pass.
- [x] Assembled `trc.plan.md` and `trc.implement.md` read, write and check off the spec in the vault, and stop when the server is absent — verify: new assertions in `tests/test-assemble-commands.sh`. Done: `tests/test-assemble-commands.sh` prints `assemble-commands: OK`.
- [x] Chain, band and README name the Obsidian store — verify: `grep -c obsidian` on each file prints 1 or more (today 0), and `tests/test-band-md-contract.sh` passes. Done: `grep -c obsidian` prints 7, 8 and 3, and band `grep -c vault` prints 4. `tests/test-band-md-contract.sh` passes.
- [x] Assembled `trc.plan.md` and `trc.implement.md` start with the setup step. It names the four `spec.obsidian` keys, the store question trigger, and the rule that a question with a key in the config is not asked again — verify: new assertions in `tests/test-assemble-commands.sh`. Done: `tests/test-assemble-commands.sh` prints `assemble-commands: OK`.
- [x] The obsidian text in the store, load, checklist and cleanup sections follows `spec.obsidian.note_name`, `frontmatter` and `done` — verify: new assertions in `tests/test-assemble-commands.sh`. Done: `tests/test-assemble-commands.sh` prints `assemble-commands: OK`.
- [x] `core/` and its mirrors agree, and the full suite passes — verify: `bash tests/run-tests.sh` exits 0. Done: `bash tests/run-tests.sh` exits 0 with 135 passed, 0 failed.

## Open Questions

None.

## Implementer Notes

Handoffs from the validator. The implementer resolves each one during the work.

- Proposed Solution, `tricycle generate mcp` — the merge loop reads each custom server back from `CONFIG_DATA` through `cfg_get`. So feed the default `obsidian` entry into that data, or write it in a separate branch. The JSON must stay valid with no preset (`preset_inner` is empty) and with a preset. (evidence: `bin/tricycle:745-826`)
- Proposed Solution, `${OBSIDIAN_VAULT_PATH}` — find out how Claude Code handles an unset variable in `.mcp.json` args. It could disable only `obsidian`. Or it could stop the whole file from loading, and the linear server would stop too. Use `${OBSIDIAN_VAULT_PATH:-}` or something similar if needed. (evidence: `bin/tricycle:788-796`)
- Proposed Solution, package `@bitbonsai/mcpvault@latest` and its Node v22.12.0 minimum — confirm the npm name and the engines field before writing the README.
- Current behavior, resolve-input — in obsidian mode, a spec id whose note `<spec.dir>/<id>.md` already exists in the vault must count as an existing spec. Today only repo mode does this check. (evidence: `core/blocks/plan/resolve-input.md:25-26`)
- Proposed Solution, the blocks — validate and validate-gate write Implementer Notes and the `Status:` line into the spec. In obsidian mode those writes must patch the note. Also, the `git diff --name-only <sha>` check in validate-gate does not see changes to the note itself. (evidence: `core/blocks/plan/validate.md:16-25`, `core/blocks/implement/validate-gate.md:13-21`)
- Current behavior, the README — the store values also appear at `README.md:375` (`# repo | linear`), not only at lines 51-58.
- Current behavior, `trc.band` — the resume check at line 144 says "exist on disk". In obsidian mode the spec must be checked in the vault through MCP. (evidence: `core/commands/trc.band.md:142-146`)
- Proposed Solution, push-deploy — the linear branch for ticket lookup at line 81 must still work in obsidian mode. Use the ticket from the Source line. (evidence: `core/blocks/implement/push-deploy.md:81`)
- Checklist, the `tricycle status` test — the existing linear test only greps for `spec.store: linear`. "The linear text does not change" needs its own assertion. (evidence: `tests/run-tests.sh:818-819`)
- Proposed Solution, `setup-store` — `list_blocks_for_step` reads only `blocks/<step>/`. So add two block files, `core/blocks/plan/setup-store.md` and `core/blocks/implement/setup-store.md`, with `order: 5` and the same body. A test checks that the two bodies are equal. (evidence: `core/scripts/bash/common.sh:64-71`)
- Proposed Solution, `setup-store` in `/trc.chain` and `/trc.band` — workers do not ask questions. The orchestrator runs the setup questions once, before it starts workers. A worker that finds a due question stops and reports it. (evidence: `core/commands/trc.chain.md:423-425`, `core/commands/trc.band.md:421-422`)
- Proposed Solution, the vault-folder question — the layout questions are one group, and the trigger is a missing `spec.obsidian` block. The vault-folder question is asked even when `spec.dir` exists. The current `spec.dir` is one of its options. (evidence: `tricycle.config.yml:18-20`)
- Proposed Solution, the store question — the default server is added only after `spec.store: obsidian` is set. So the store question fires only for an `obsidian` server from `mcp.custom.obsidian` or from outside the repo. The README tells other users to set `spec.store: obsidian` by hand. (evidence: `bin/tricycle:744-746`)
