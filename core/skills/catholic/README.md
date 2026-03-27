# Catholic Skill

Applies reverent, faith-inspired Christian verbiage to non-code artifacts.

## Installation

This skill ships with Tricycle Pro but is NOT installed by default. To install:

```bash
tricycle update
```

Then enable it in your workflow:

```yaml
workflow:
  blocks:
    specify:
      skills:
        - catholic
    plan:
      skills:
        - catholic
```

Run `tricycle assemble` to rebuild commands with the skill invocation.

## Usage

Invoke manually:
```
/catholic
```

Or configure it on workflow steps (specify, plan, implement) via `tricycle.config.yml` as shown above.

## What it does

- Adds opening blessings and closing thanksgivings to specs, plans, task lists, and READMEs
- References Providence, divine guidance, gratitude, and stewardship
- Never touches source code, tests, config files, or executable content

## What it does NOT do

- Quote scripture at length
- Make doctrinal arguments
- Apply religious language to code
- Override technical content with religious content

## Customization

Edit `.claude/skills/catholic/SKILL.md` to adjust the tone, add patron saint references, or modify the verbiage examples.
