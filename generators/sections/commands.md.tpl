## Commands

{{#each apps}}
- **{{app.name}}**: {{#if app.lint}}`cd {{app.path}} && {{app.lint}}` (lint) {{/if}}{{#if app.test}}`cd {{app.path}} && {{app.test}}` (test){{/if}}
{{/each}}

{{#if project.package_manager}}
### Package Manager
{{project.package_manager}} only. Do not mix package managers.
{{/if}}
