# Spec Delta

## Purpose

Defines the HTTP/JSON API through which browsers, scripts, and services without an Arrow client submit queries, fetch results, cancel queries, and manage the catalog.

## ADDED Requirements

### Requirement: HTTP API on a dedicated port
The scheduler SHALL serve the HTTP API on a configured port separate from the Flight SQL and cluster-internal ports, with all `/v1/*` routes requiring authentication as defined in `access-control`.

#### Scenario: Unauthenticated request
- **WHEN** a request to `/v1/statement` carries no credentials
- **THEN** the response is HTTP 401 with a JSON error body

### Requirement: Login and sessions
`POST /v1/login` with Basic credentials SHALL return a bearer token bound to a new private session. A request carrying Basic credentials instead of a token SHALL be served from an implicit session that is shared by all Basic-authenticated requests of that user and expires like any session.

#### Scenario: Token login
- **WHEN** a client posts to `/v1/login` with valid Basic credentials
- **THEN** the response is HTTP 200 with `{ "token", "expires_in" }`, where `expires_in` is the session idle timeout in seconds, and the token is accepted as `Authorization: Bearer` on every `/v1` route

#### Scenario: Basic-only client
- **WHEN** a client submits a statement with Basic credentials and fetches `nextUri` with the same credentials from a different connection
- **THEN** the fetch succeeds

Statement ownership (owner from any session, admins, HTTP 403 for others) is defined once in `access-control` and applies to every `/v1/statement*` route.

### Requirement: Submit a statement
`POST /v1/statement` with a JSON body `{ "sql": "...", "session": {...optional settings...} }` SHALL parse the SQL synchronously, then create a query and return HTTP 202 with `{ "id", "state", "nextUri" }` without waiting for planning or execution to finish; planning errors SHALL be reported as state `FAILED` on the first fetch.

#### Scenario: Submit returns handle
- **WHEN** a client posts a long-running query over a large table
- **THEN** the response arrives within one second with state `QUEUED` or `RUNNING` and a `nextUri`, even if planning that query takes longer

#### Scenario: Syntax error
- **WHEN** the SQL does not parse
- **THEN** the response is HTTP 400 with `{ "error": { "message", "code" } }` and no query is created

#### Scenario: Planning error
- **WHEN** the SQL parses but names an unknown table
- **THEN** the response is HTTP 202 and the first fetch returns state `FAILED` with the planning error and no `nextUri`

### Requirement: Fetch results in pages
`GET /v1/statement/{id}/{page}` SHALL return the query state, column metadata, a page of rows, and `nextUri` while more pages exist; while the query is still running the page SHALL carry no rows and a `nextUri` pointing at the same page; the final page SHALL omit `nextUri` and include execution statistics.

#### Scenario: Paging through results
- **WHEN** a client follows `nextUri` until it is absent
- **THEN** the concatenated pages contain exactly the query's rows in result order, each page at most the configured page size

#### Scenario: Retrying the current page
- **WHEN** a client re-requests the page it most recently received
- **THEN** the same rows are returned and the cursor does not advance

#### Scenario: Requesting an earlier page
- **WHEN** a client requests a page older than the one most recently served
- **THEN** the response is HTTP 410 Gone

#### Scenario: Query failed
- **WHEN** the query fails during execution
- **THEN** the next fetch returns state `FAILED` with the error and no `nextUri`

### Requirement: Arrow IPC results
When a fetch request carries `Accept: application/vnd.apache.arrow.stream`, the gateway SHALL return the page as an Arrow IPC stream instead of JSON rows, with the same paging semantics carried in a `Link: <nextUri>; rel="next"` response header (absent on the final page) and the query state in an `X-Octopus-State` header.

#### Scenario: Arrow page
- **WHEN** a client fetches a page with the Arrow accept header
- **THEN** the body is a valid Arrow IPC stream whose schema matches the query result

### Requirement: JSON type mapping
JSON results SHALL encode Arrow values deterministically: integers and floats as JSON numbers (64-bit integers as strings when they exceed 2^53), decimals as strings, dates and timestamps as ISO 8601 strings, binary as base64, nested structs and lists as JSON objects and arrays, and nulls as `null`; the column metadata SHALL state the Arrow type of each column.

#### Scenario: Mixed types
- **WHEN** a query returns `DECIMAL`, `TIMESTAMP WITH TIME ZONE`, and a `LIST<INT>` column
- **THEN** the JSON page encodes each as specified and column metadata names the types

### Requirement: Cancel a statement
`DELETE /v1/statement/{id}` SHALL cancel the query and return HTTP 204; subsequent fetches SHALL report state `CANCELLED`.

#### Scenario: Cancel running query
- **WHEN** a client deletes a running statement
- **THEN** cluster tasks stop within five seconds and the state is `CANCELLED`

### Requirement: Abandoned statements expire
A statement whose results are not fetched within a configured idle timeout SHALL be cancelled and its results released.

#### Scenario: Client never fetches
- **WHEN** a client submits a query and makes no further request for the idle timeout
- **THEN** the query is cancelled if running and its result pages are no longer retrievable

### Requirement: Catalog endpoints
The gateway SHALL expose `GET|POST /v1/catalog/schemas`, `DELETE /v1/catalog/schemas/{schema}[?cascade=true]`, `GET|POST /v1/catalog/schemas/{schema}/tables`, and `GET|DELETE /v1/catalog/schemas/{schema}/tables/{table}` plus `POST .../tables/{table}/refresh`, with the same semantics and role checks as the SQL DDL.

#### Scenario: Register table over HTTP
- **WHEN** an admin posts `{ "name": "orders", "format": "parquet", "location": "s3://data/tpch/orders/", "partitioned_by": [{ "name": "o_orderdate", "type": "DATE" }] }`
- **THEN** the response is HTTP 201 with the inferred schema and the table is queryable

#### Scenario: Describe table over HTTP
- **WHEN** a client gets `/v1/catalog/schemas/{schema}/tables/{table}`
- **THEN** the body contains the format, location, options, partition columns, and Arrow schema of the table

#### Scenario: Drop non-empty schema over HTTP
- **WHEN** an admin deletes a schema that contains tables without `cascade=true`
- **THEN** the response is HTTP 409 and the schema is unchanged

#### Scenario: Reader cannot register
- **WHEN** a reader posts to the tables endpoint
- **THEN** the response is HTTP 403

### Requirement: Query listing for the caller
`GET /v1/statements` SHALL list the caller's recent statements with state and timing; admins SHALL see all users' statements.

#### Scenario: Reader sees own queries only
- **WHEN** a reader lists statements
- **THEN** only statements submitted by that user are returned

### Requirement: OpenAPI description
The gateway SHALL serve an OpenAPI 3 document at `/v1/openapi.json` describing every `/v1` route.

#### Scenario: Spec is valid
- **WHEN** the document is fetched and validated with a standard OpenAPI validator
- **THEN** it validates without errors and lists all routes above

### Requirement: Monitoring API passthrough
The gateway SHALL expose the scheduler monitoring REST API (`/api/*`, as defined in `observability`) on the same port, restricted to users with the `admin` role.

#### Scenario: Jobs list via gateway
- **WHEN** an admin requests `/api/jobs`
- **THEN** the job list is returned

#### Scenario: Reader denied
- **WHEN** a reader requests any `/api/*` route
- **THEN** the response is HTTP 403

### Requirement: Monitoring UI served by the gateway
The gateway SHALL serve the monitoring web UI at `/ui` on the same origin as `/api`, so that the UI authenticates with the same credentials.

#### Scenario: UI loads behind auth
- **WHEN** an admin opens `/ui` in a browser and enters credentials at the browser prompt
- **THEN** the UI loads and displays executors and queries fetched from `/api`
