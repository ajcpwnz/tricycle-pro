## Docker (MANDATORY)

When you need to run migrations or tests that require the database:
1. Check if Docker is running and containers are up (`docker ps`).
2. If containers are down, start them before proceeding.
{{#each apps}}
{{#if app.docker}}
- **{{app.name}}**: `cd {{app.path}} && docker compose up -d`
{{/if}}
{{/each}}
