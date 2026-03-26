---
name: prerequisites
step: implement
description: Run check-prerequisites.sh with tasks requirement
required: true
default_enabled: true
order: 20
---

1. Run `.trc/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").
