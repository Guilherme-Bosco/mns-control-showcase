# Samples

Sanitized excerpts from the MNS Control production code base. The full source is closed.

Secrets, URLs and identifiers were replaced with placeholders such as `<SUPABASE_URL>`. Apart from that, this is the code that runs in production. Code comments are in Portuguese, as in the original. Each file starts with a short English header that says where it came from and what it shows.

## Database (PostgreSQL / Supabase)

| File | What it is |
|---|---|
| [db/01_rls_multitenant.sql](db/01_rls_multitenant.sql) | Row-Level Security for every business table, built on the `get_user_role()` and `get_user_tenant_id()` helper functions, plus a trigger that stops a user from changing their own role or tenant. Extracted from the live catalog. |
| [db/02_trigger_atualizar_status_cliente.sql](db/02_trigger_atualizar_status_cliente.sql) | PL/pgSQL trigger that recalculates a client's status and totals whenever a service changes status. |

## Back end (TypeScript)

| File | What it is |
|---|---|
| [backend/acao-route.ts](backend/acao-route.ts) | The Next.js route that every dashboard action goes through before it reaches n8n. It takes the tenant from the session and ignores the one sent by the browser. |

## Automation (n8n)

| File | What it is |
|---|---|
| [n8n/monitor-sessao-waha.json](n8n/monitor-sessao-waha.json) | Session monitor workflow, exported from n8n with credentials and IDs removed. It polls every WhatsApp session every 5 minutes, writes the current state to the database, and sends one alert per outage, deduplicated in Redis. |
