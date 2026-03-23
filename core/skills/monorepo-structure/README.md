# Skill: monorepo-spec-kit-structure

## Purpose

This Skill teaches Claude a consistent, reusable way to structure
**spec-driven monorepos** that use Spec-Kit (or similar tools) with
frontend, backend, and specs in a single repository.

It standardizes:

- Where specs live and how they are organized.
- How frontend and backend code are separated.
- How `CLAUDE.md` files are layered for different parts of the repo.
- How AI agents should navigate and modify the project without guessing.

The goal is that any AI-driven monorepo can reuse the same layout
instead of inventing a new structure for every project.

## What this Skill defines

- **SKILL.md** – Rules and patterns for:
  - Recommended top-level folders: `/.spec-kit`, `/specs`, `/frontend`,
    `/backend`, optional `/infra` or `/deploy`.
  - Organizing specs under `/specs` by type:
    - `overview`, `architecture`, `features`, `api`, `database`, `ui`,
      optional `infra`.
  - Keeping `.spec-kit/config.yaml` in sync with the actual folder
    structure.
  - Layering `CLAUDE.md` files at root, frontend, and backend levels
    so instructions stay clear and non-conflicting.

- **Templates/**
  - `root-CLAUDE.md.tpl`
    Standard root `CLAUDE.md` skeleton for a spec-driven monorepo:
    - Explains the project layout.
    - Documents the `/specs` structure and how to reference specs
      (e.g. `@specs/features/...`).
    - Defines the spec-driven development workflow:
      - Read specs → Plan → Implement → Test → Update docs.
    - Explains how root, `frontend/CLAUDE.md`, and `backend/CLAUDE.md`
      coordinate.

- **Examples/**
  - `monorepo-layout.md`
    Shows GOOD vs BAD repository layouts:
    - GOOD: clear `/specs`, `/frontend`, `/backend`, `/.spec-kit`, and
      matching Spec-Kit config.
    - BAD: specs scattered in random folders, mixed with code, no clear
      CLAUDE instructions.

## When to enable this Skill

Enable/use this Skill in any project where:

- You are using a **monorepo** for frontend + backend + specs.
- You are using Spec-Kit or a similar spec-driven tool to manage
  Markdown specifications.
- You want AI agents (e.g. Claude Code) to:
  - Always start from specs.
  - Understand project layout without guesswork.
  - Respect frontend/backend/infra boundaries.

It is especially useful for AI-native, spec-driven projects where
multiple phases or components share the same repo.

## How to integrate in a project

Typical integration steps:

1. Align your top-level layout with the recommended structure:

   - `/.spec-kit/` – Spec-Kit config (`config.yaml`) and internal data.
   - `/specs/` – all specifications, organized by type.
   - `/frontend/` – frontend app(s).
   - `/backend/` – backend app(s).
   - Optional `/infra/` or `/deploy/` – deployment and ops files.

2. Organize specs under `/specs`:

   - Create `overview.md` and `architecture.md`.
   - Create subfolders:
     - `specs/features/`
     - `specs/api/`
     - `specs/database/`
     - `specs/ui/`
     - `specs/infra/` (if needed)

3. Configure Spec-Kit:

   - Create or update `.spec-kit/config.yaml` to point to the correct
     `specs_dir` and subdirectories.

4. Generate and adapt a root `CLAUDE.md` from `root-CLAUDE.md.tpl`:

   - Describe your specific project.
   - Keep the structure and workflow sections aligned with this Skill.

5. Add layer-specific CLAUDE files:

   - `frontend/CLAUDE.md` for frontend rules.
   - `backend/CLAUDE.md` for backend rules.

After this, Claude should consistently navigate the monorepo, read the
right specs, and apply changes in the correct layer using a predictable,
spec-driven workflow.
