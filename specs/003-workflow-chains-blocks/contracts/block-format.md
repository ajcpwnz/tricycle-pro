# Contract: Block File Format

**Feature**: 003-workflow-chains-blocks
**Date**: 2026-03-24

## Block File Structure

Markdown files with YAML frontmatter stored in:
- Built-in: `core/blocks/{step}/{block-name}.md` → `.trc/blocks/{step}/{block-name}.md`
- Custom: Any path referenced in `workflow.blocks.{step}.custom`

## Frontmatter Schema

```yaml
---
name: spec-writer
step: specify
description: Generate specification content from feature description
required: false
default_enabled: true
order: 40
---
```

| Field | Type | Required | Values |
|-------|------|----------|--------|
| name | string | yes | `/^[a-z][a-z0-9-]*$/`, unique per step |
| step | string | yes | specify, plan, tasks, implement |
| description | string | yes | One-line description |
| required | boolean | yes | true = cannot be disabled |
| default_enabled | boolean | yes | true = included in default assembly |
| order | integer | yes | 10-999, built-in use multiples of 10 |

## Body Content

Everything below closing `---` is the block's prompt content — instructions the AI agent follows. Concatenated during assembly to form the complete command file.

## Assembly Output

```markdown
---
description: [Generated from step + block metadata]
handoffs: [Determined by chain — next step]
---

## User Input
[Standard $ARGUMENTS block — always first]

[Block content at order 10]

[Block content at order 20]

...
```
