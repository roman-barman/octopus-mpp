# octopus-gateway

The HTTP API served by the scheduler process.

**Single responsibility:** an axum router that lets clients without an Arrow
client submit queries (`POST /v1/statement`), page through results as JSON or
Arrow IPC, cancel and list statements, manage the catalog over HTTP, and read
the OpenAPI description; it also mounts the Ballista monitoring REST API,
query history, and the monitoring UI behind admin-only authentication. It
calls the same session and query machinery as the Flight SQL endpoint, never
Flight SQL over the network.

Depends on `octopus-config`, `octopus-catalog`, `octopus-auth`, and
`octopus-session`. Used by `octopus-scheduler`.
