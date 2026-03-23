# Monorepo + Spec-Kit Layout (Example)

## GOOD: Clear, spec-driven monorepo

- Top-level structure:

  - `/.spec-kit/` – Spec-Kit config and internal data.
  - `/specs/` – all specifications, organized by type.
  - `/frontend/` – frontend app(s).
  - `/backend/` – backend app(s).
  - Optional `/infra/` or `/deploy/` – deployment, K8s, Dapr, CI/CD files.

- Specs are organized and easy to find:

  - `specs/overview.md` – project summary and current phase.
  - `specs/architecture.md` – high-level architecture.
  - `specs/features/` – feature specs, one per feature.
  - `specs/api/` – API endpoint and protocol specs.
  - `specs/database/` – schema and model specs.
  - `specs/ui/` – UI components, pages, flows.
  - `specs/infra/` – infrastructure and deployment specs (if used).

- Spec-Kit configuration matches the folder layout:

  - `.spec-kit/config.yaml` points `specs_dir` to `specs`
    and subdirectories to the correct paths.

- CLAUDE.md files are layered:

  - Root `CLAUDE.md` explains:
    - Monorepo layout.
    - Specs folders.
    - Spec-driven workflow.
  - `frontend/CLAUDE.md` defines frontend stack rules.
  - `backend/CLAUDE.md` defines backend stack rules.

Result:

- AI agents can quickly:
  - Locate the right specs.
  - Understand where to edit code.
  - Respect frontend/backend/infra boundaries.
- New features always start from `/specs`, then map cleanly into code.

## BAD: Mixed, ad-hoc layout

- Specs are scattered or missing:

  - Some specs live in `/docs`, others under `/backend`, some only in
    comments or not written at all.
  - No clear `/specs` root; Spec-Kit config is missing or out of date.

- Code and specs are mixed:

  - Feature descriptions are embedded in source files instead of
    dedicated spec files.
  - Frontend and backend logic live in the same folders.

- No clear CLAUDE instructions:

  - Only one giant `CLAUDE.md` at the root with mixed frontend, backend,
    and infra rules.
  - AI agents have to guess where to apply changes.

Result:

- Hard for humans and AI to find the correct specs.
- Easy to accidentally edit the wrong layer (e.g. backend code from a
  frontend context).
- Specs, config, and code drift out of sync.
