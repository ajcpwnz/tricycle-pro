# Catholic Skill

Applies reverent, faith-inspired Christian verbiage to non-code artifacts.

## Installation

This skill ships with Tricycle Pro, and `tricycle init` and `tricycle update` install it. To leave it out, add it to `skills.disable` in `tricycle.config.yml`.

The matching **catholic block** opens and closes `/trc.plan` with a prayer. Turn it on with `workflow.blocks.plan.enable: [catholic]`, then run `tricycle assemble`.

## Usage

Invoke manually:
```
/catholic
```

Claude Code also invokes it on its own when its description fits the work.

## What it does

- Adds opening blessings and closing thanksgivings to specs and READMEs
- References Providence, divine guidance, gratitude, and stewardship
- Never touches source code, tests, config files, or executable content

## What it does NOT do

- Quote scripture at length
- Make doctrinal arguments
- Apply religious language to code
- Override technical content with religious content

## Customization

Edit `.claude/skills/catholic/SKILL.md` to adjust the tone, add patron saint references, or modify the verbiage examples.
