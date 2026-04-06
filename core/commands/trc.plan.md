---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs:
  - label: Create Tasks
    agent: trc.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: trc.checklist
    prompt: Create a checklist for the following domain...
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).


## Chain Validation

Before proceeding, read `tricycle.config.yml` and check the `workflow.chain` configuration.

1. If `workflow.chain` is not defined, use the default chain: `[specify, plan, tasks, implement]`.
2. Validate the chain is one of these valid configurations:
   - `[specify, plan, tasks, implement]` (default — full workflow)
   - `[specify, plan, implement]` (tasks absorbed into plan)
   - `[specify, implement]` (plan and tasks absorbed into specify)
3. If the chain is invalid, STOP and output:
   ```
   Error: Invalid workflow chain configuration.
   Valid chains: [specify, plan, tasks, implement], [specify, plan, implement], [specify, implement]
   ```
4. Verify that `plan` is present in the configured chain. If not, STOP and output:
   ```
   Error: Step 'plan' is not part of the configured workflow chain [current chain].
   To use this step, update workflow.chain in tricycle.config.yml and run tricycle assemble.
   ```


1. **Setup**: Run `.trc/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.trc/memory/constitution.md`. Load IMPL_PLAN template (already copied).

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications


- Fill Constitution Check section from constitution
- Evaluate gates (ERROR if violations unjustified)
- Re-evaluate Constitution Check post-design


### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved


### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Define interface contracts** (if project has external interfaces) → `/contracts/`:
   - Identify what interfaces the project exposes to users or other systems
   - Document the contract format appropriate for the project type
   - Examples: public APIs for libraries, command schemas for CLI tools, endpoints for web services, grammars for parsers, UI contracts for applications
   - Skip if project is purely internal (build scripts, one-off tools, etc.)

**Output**: data-model.md, /contracts/*, quickstart.md


3. **Agent context update**:
   - Run `.trc/scripts/bash/update-agent-context.sh claude`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers


4. **Version awareness**: Read the `VERSION` file from the repo root. Note the current version in the plan summary. The implementation phase (`/trc.implement`) will bump this version upon completion — the plan should note whether the feature warrants a minor bump (new feature) or patch bump (fix/improvement).

5. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.


## Skill Invocations

The following skills are configured for the `plan` step. Invoke each one if installed; skip gracefully if not.

- If `.claude/skills/document-writer/SKILL.md` exists, invoke `/document-writer`. If the skill is not installed, skip this invocation and continue.

Context for invocation: 

