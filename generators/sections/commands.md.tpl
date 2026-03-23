## Commands

{{#each apps}}
- **{{app.name}}**: `cd {{app.path}} && {{app.lint}}` (lint), `cd {{app.path}} && {{app.test}}` (test)
{{/each}}

### Package Manager
{{project.package_manager}} only. Do not mix package managers.
