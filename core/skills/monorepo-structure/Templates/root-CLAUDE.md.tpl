# Project Overview

This is a spec-driven, AI-native monorepo managed with Spec-Kit and
edited primarily via AI tools (e.g. Claude Code).

The repository contains:

- `/specs` – project specifications (features, API, database, UI, infra).
- `/frontend` – frontend application(s).
- `/backend` – backend application(s).
- Optional `/infra` or `/deploy` – infrastructure, Kubernetes, Dapr, CI/CD.

Your primary job as an AI agent is to read the relevant specs first,
then implement or modify code in the correct layer without guessing
beyond what the specs allow.

---

## Specs Directory

All requirements and architecture live in `/specs`:

- `specs/overview.md` – high-level project overview and current phase.
- `specs/architecture.md` – system architecture and data flow.
- `specs/features/` – feature specs, one file per feature.
- `specs/api/` – REST/HTTP/MCP API contracts.
- `specs/database/` – database schema and models.
- `specs/ui/` – UI/UX components, pages, and flows.
- `specs/infra/` (optional) – deployment, K8s, Dapr, Kafka, CI/CD.

Always reference specs explicitly when working, for example:

- `@specs/features/task-crud.md`
- `@specs/api/rest-endpoints.md`
- `@specs/database/schema.md`

If the necessary spec is missing or incomplete, stop and request a spec
update instead of inventing new behaviour.

---

## Code Structure

### Frontend

The frontend lives under `/frontend`:

- Follow the framework-specific CLAUDE instructions in `frontend/CLAUDE.md`.
- Do not modify backend or infra code from the frontend context.
- Keep UI, routing, and API calls aligned with the specs in `/specs/ui`
  and `/specs/api`.

### Backend

The backend lives under `/backend`:

- Follow `backend/CLAUDE.md` for stack-specific rules (e.g. FastAPI,
  SQLModel, Agents SDK, MCP SDK).
- Keep models, routes, services, and tools aligned with `/specs/api`
  and `/specs/database`.

Do not mix frontend and backend code in the same folders.

---

## Spec-Driven Development Workflow

Always follow this workflow:

1. **Read specs**
   - Identify relevant files in `/specs` for the requested change.
   - If requirements are unclear or missing, request a spec update.

2. **Plan changes**
   - Derive a short plan from the specs (which files, which layers,
     which tests).
   - Ensure the plan respects monorepo boundaries and existing
     conventions.

3. **Implement**
   - Apply changes only in the appropriate folders (`/frontend`,
     `/backend`, `/infra`) according to the plan.
   - Keep changes minimal and aligned with the specs.

4. **Test and verify**
   - Propose or update tests to cover acceptance criteria from the specs.
   - Avoid introducing breaking changes that are not justified by specs.

5. **Update docs if needed**
   - When specs evolve, ensure they remain the source of truth.

---

## Coordination With Layer-Specific CLAUDE Files

- Use this root `CLAUDE.md` for:
  - Understanding monorepo layout.
  - Learning how specs, code, and tools are organized.

- Use `frontend/CLAUDE.md` for:
  - Framework-specific rules (e.g. Next.js structure, styling, API usage).

- Use `backend/CLAUDE.md` for:
  - Backend-specific rules (e.g. FastAPI routers, models, agents, tools).

If there is ever a conflict:

- Global principles here (spec-driven, monorepo boundaries) take
  precedence.
- Layer-specific files refine behaviour within their own folder.

---

## General Rules

- Do not perform "vibe coding". All significant changes must be justified
  by specs.
- Do not move or rename top-level folders (`specs`, `frontend`, `backend`,
  `infra`) unless explicitly instructed.
- Keep code, specs, and configuration in sync; avoid leaving dead or
  orphaned files behind.
