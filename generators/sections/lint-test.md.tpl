## Lint & Test Before Done (MANDATORY — NONNEGOTIABLE)

After ANY code changes, you MUST run lint and test scripts for ALL affected apps/packages
and ensure they pass BEFORE declaring work complete.

{{#each apps}}
- **{{app.name}}**: `cd {{app.path}} && {{app.lint}}`{{#if app.test}} `&& {{app.test}}`{{/if}}
{{/each}}

If any script fails, fix the issue. Never skip this step.
