# Design

## Context

See `proposal.md` for motivation. This section records only the facts about the starting point that shape the design.

- **Greenfield repository.** Nothing exists yet except OpenSpec scaffolding.
- **Ballista 55 (DataFusion 55, Arrow 59)** is the base. Observed state of `apache/datafusion-ballista` at `main` on 2026-11-06:
  - Crates: `ballista-core`, `ballista-scheduler`, `ballista-executor`, `ballista-client`, `ballista-flight-sql`, `ballista-history`, `ballista-result-service`, `ballista-api-types`.
  - Scheduler extension points (`SchedulerConfig`): `override_session_builder`, `override_config_producer`, `override_logical_codec`, `override_physical_codec`, `override_flight_sql_authenticator`, `adaptive_rules`, `job_id_generator`. Executor extension points (`ExecutorProcessConfig`): function registry, runtime producer, config producer, codecs.
  - Flight SQL frontend exists (`BallistaFlightSqlService` over a public `QueryBackend` trait with `session`, `close_session`, `execute`; pluggable `Authenticator` returning an `Identity` per request) but: is mounted on the **same gRPC port** as the executor-facing scheduler API (`flight_sql: bool`, no separate address); has **no** `PollFlightInfo`, **no** cancellation, **no** parameter binding; result tickets carry executor addresses that are **not validated**; unauthenticated clients share one anonymous session; sessions and their catalogs are in-memory and expire after 30 minutes idle.
  - Cluster state has one backend: in-memory. Catalog state per session only.
  - REST monitoring API (`/api/*`, OpenAPI, including `/api/job/{id}/stages`), Web TUI (hosted, talks to REST via CORS), history server (JSON Lines event log, separate process), `/healthz`, `/readyz`, graceful shutdown, protocol-version check all exist. Prometheus metrics (`scheduler/src/metrics/prometheus.rs`, verified 2026-11-11) are **job-level only**: `job_submitted_total`, `job_completed_total`, `job_failed_total`, `job_cancelled_total`, `job_exec_time_seconds`, `planning_time_ms`, `pending_task_queue_size`. There are no per-executor series and no labels.
  - Staged execution (default, AQE on) and pipelined execution (experimental, needs push-staged scheduling, no AQE, no retries).
  - `ballista-core::object_store` provides an S3-capable `ObjectStoreRegistry` driven by SQL `SET` options; it is an example pattern, not a requirement to reuse.
- **delta-rs 2.0** targets DataFusion 55 / Arrow 59 and ships `DeltaTableProvider`, `DeltaLogicalCodec`, and `DeltaPhysicalCodec`, i.e. the pieces needed to ship Delta scans through Ballista's plan serialization.
- **Constraints from the project owner:** Ballista stays a dependency (no fork); every upstream task and PR is agreed with and reviewed by the owner before it is opened; the owner must be able to understand all code; project artifacts are in English; the reference test environment is Docker Compose with scheduler and executors in separate containers.

## Goals / Non-Goals

**Goals:**
- A codebase where each crate has one job, every Ballista extension point we use is named and explained, and a reader can follow a query from client to executor through our code and the documented Ballista boundaries.
- Keep our code thin: product features (catalog, auth, gateway, Delta wiring, config) live in our crates; distributed execution stays in Ballista.
- Make upstream-dependent work explicit and isolated so that the project can progress on a pinned branch while upstream review happens.

**Non-Goals (design-level):**
- Replacing Ballista's scheduler internals, shuffle, or AQE.
- A custom UI, a custom cluster-state store, or multi-scheduler coordination.
- Performance work beyond sensible defaults; no benchmarking targets in this change.

## Decisions

### D1. Ballista as a dependency, upstream-first for internal gaps

Use the Ballista crates from crates.io (or a git pin on `apache/datafusion-ballista`) and build everything through public extension points. Changes that must land inside Ballista are listed in *D12* and are developed on a fork branch under our control **only** as a staging area for upstream PRs; `Cargo.toml` pins that branch until the PR merges and a release ships. Each such item is proposed to the owner first (scope, approach, diff) and opened upstream only after the owner's review.

*Alternatives:* permanent fork (rejected: Ballista ships a major every DataFusion major; merging that forever is the whole budget); DataFusion Distributed (rejected: library without scheduler, cluster state, or fault tolerance; we would rebuild Ballista).

### D2. Workspace layout

```
octopus-mpp/
  Cargo.toml                 workspace, shared [workspace.dependencies] pinned to Ballista 55.x
  crates/
    octopus-config/          TOML + env config types for both processes; redaction; validation
    octopus-storage/         ObjectStoreRegistry for s3:// (MinIO) and file://, built from config
    octopus-catalog/         CatalogStore trait, SQLite store, DataFusion CatalogProvider/SchemaProvider,
                             table providers factory (parquet, delta), DDL handling
    octopus-auth/            users/roles, Argon2id verification, token store, Ballista Authenticator,
                             axum middleware, role checks
    octopus-session/         SessionBuilder: builds a DataFusion SessionState per session with our
                             catalog, storage, codecs, Ballista functions/optimizer rules, octopus.* options
    octopus-gateway/         axum HTTP API: statements, paging (JSON / Arrow IPC), catalog endpoints,
                             OpenAPI, monitoring passthrough
    octopus-scheduler/       binary: wires ballista-scheduler + flight-sql + gateway + auth + catalog
    octopus-executor/        binary: wires ballista-executor + storage + codecs
  deploy/compose/            docker-compose.yml, scheduler.toml, executor.toml, MinIO bootstrap
  tests/integration/         Rust integration tests driving the Compose stand (Flight SQL + HTTP),
                             TPC-H generation, reference results
  docs/
    architecture.md          components, ports, query lifecycle diagram
    adr/                     one file per decision below (ADR-0001 ...)
    operations.md            configuration reference, running the stand
    clients.md               DataGrip, ADBC, curl recipes
    upstream-patches.md      every local patch on the pinned Ballista branch and its upstream status
```

One crate per responsibility, no crate depends on a binary crate, and the two binaries contain only wiring. This is the main instrument for the "understand all the code" goal. The one deliberate exception: `octopus-scheduler` also links `ballista-executor` for `--standalone` (D3), so the scheduler binary is heavier than pure wiring would need.

*Alternative:* a single crate with modules (rejected: compile times and blurred boundaries as soon as the gateway and catalog grow).

### D3. Two binaries, three scheduler ports

The scheduler process serves:

| Port (config key)            | Protocol                          | Audience          |
|------------------------------|-----------------------------------|-------------------|
| `cluster.bind_port` (50050)  | Ballista gRPC (executor API)      | executors only    |
| `flight_sql.bind_port` (50060) | Arrow Flight SQL (gRPC)         | clients           |
| `http.bind_port` (8080)      | HTTP: `/v1/*`, `/api/*`, `/metrics`, probes | clients, operators |

Ballista mounts Flight SQL on the cluster port. We instead construct `BallistaFlightSqlService` ourselves on a separate tonic server, backed by the scheduler's `QueryBackend` implementation. The trait is public; whether the scheduler's implementation of it is constructible from outside the crate is checked first in task 6.4, and only if it is not does the fix become an upstream item (*D12-a*) living on the pinned branch until merged. The cluster port is never published outside the cluster network; the Compose file only publishes the two client ports.

The cluster port also carries Ballista's native client RPCs (`ExecuteQuery`, `ExecuteQueryPush`, `CreateUpdateSession`, `GetJobStatus`, `CancelJob`, ...), which are unauthenticated. **The Ballista native client is not a supported client of octopus-mpp.** We build the cluster-port tonic server ourselves and add an interceptor that rejects every RPC except the executor-facing ones (`RegisterExecutor`, `HeartBeatFromExecutor`, `PollWork`, `UpdateTaskStatus`, `ExecutorStopped`) with `PERMISSION_DENIED`. Network isolation is defence in depth, not the only control. If the server cannot be assembled from public items, this becomes upstream item *D12-f*.

*Bootstrapping note (Phase 3 of tasks).* Before our Flight SQL port exists, the stand's smoke tests use Ballista's built-in Flight SQL on the cluster port through a `compose.dev.yml` override that publishes it on localhost. The production Compose file never does; the override is removed when Phase 6 lands.

Result data reaches clients **through the scheduler process** (Ballista's `advertise_flight_endpoint` pointed at our Flight SQL port, which also serves plain Flight `DoGet` for result tickets) so that clients never need executor access. A separate `ballista-result-service` is not used in v1; it can be added later for scale without changing client behavior.

### D4. Persistent catalog in SQLite behind a trait

`octopus-catalog` defines:

```rust
trait CatalogStore {            // sync, small, transactional
    fn list_schemas(&self) -> Result<Vec<SchemaDef>>;
    fn create_schema(&self, s: &SchemaDef) -> Result<()>;
    fn drop_schema(&self, name: &str, cascade: bool) -> Result<()>;
    fn list_tables(&self, schema: &str) -> Result<Vec<TableDef>>;
    fn get_table(&self, schema: &str, name: &str) -> Result<Option<TableDef>>;
    fn create_table(&self, t: &TableDef) -> Result<()>;
    fn update_table_schema(&self, schema: &str, name: &str, arrow: &Schema) -> Result<()>;
    fn drop_table(&self, schema: &str, name: &str) -> Result<()>;
}
struct TableDef { schema, name, format: Parquet | Delta, location: Url,
                  partition_columns: Vec<(String, DataType)>, options: BTreeMap<String,String>,
                  arrow_schema: Option<Schema> /* persisted for Parquet, None for Delta */ }
```

The v1 implementation is `SqliteCatalogStore` (`rusqlite`, bundled SQLite, single file under the scheduler data directory, WAL mode). A single catalog named `octopus` exists in v1; the three-level name is kept in the API so a second catalog or an external metastore adapter is additive.

An `OctopusCatalogProvider` implements DataFusion's `CatalogProvider`/`SchemaProvider` over the store and builds `TableProvider`s at planning time: `ListingTable` (DataFusion) for Parquet with the persisted schema (it lists the location on every query, so new files appear without caching tricks), `DeltaTableProvider` (delta-rs) for Delta, **resolving the latest (or pinned) snapshot on every planning** so an external commit is visible to the very next query, as `table-catalog` and `delta-lake-source` promise. Only `TableDef` rows are cached (invalidated on DDL), never providers: a provider cache with a TTL would make the "next query sees the new commit" scenarios false for the length of the TTL. Because the catalog provider is shared, every session sees the same tables immediately.

DDL and session-scope statements are intercepted **before** DataFusion executes them: `octopus-session` inspects the parsed statement; `CREATE EXTERNAL TABLE`, `DROP TABLE`, `CREATE/DROP SCHEMA`, `ALTER TABLE ... REFRESH SCHEMA` are handled by `octopus-catalog` (schema inference, store write, cache invalidation) and never reach Ballista's per-session in-memory catalog. `USE <catalog>.<schema>` and `SET SCHEMA <schema>` are not executed by DataFusion either; `octopus-session` translates them into updates of the session's `datafusion.catalog.default_catalog`/`default_schema` options after checking the schema exists. Read statements pass through untouched.

*Alternatives:* JSON file (rejected: no transactions, awkward concurrent writes from HTTP and SQL); embedded KV such as `redb`/`sled` (rejected: SQLite is better understood and inspectable with standard tools); Postgres (deferred: becomes relevant only with multiple schedulers; the trait makes it a drop-in).

### D5. Object storage configuration

`octopus-storage` builds an `ObjectStoreRegistry` from `[storage.s3]` in the process configuration (endpoint, region, access key, secret key, session token, `path_style`, `allow_http`) and registers `file://` for local development. The same registry is installed in the scheduler's `RuntimeEnv` (planning, schema inference, Delta log reads) and in the executor's (scans). SQL `SET` of storage credentials is rejected (we do not install Ballista's `S3Options` config extension). delta-rs receives the same credentials through its storage options map so Delta log reads use the same endpoint.

*Alternative:* Ballista's `CustomObjectStoreRegistry` driven by `SET` (rejected: credentials in SQL are a security and auditing problem and are per-session, not per-cluster).

### D6. Sessions and authentication

- `octopus-auth` holds `Users` (from config: name, Argon2id hash, role), a `TokenStore` (random 256-bit opaque tokens → `SessionInfo { user, role, session_id, last_seen }`, idle TTL from config), and two adapters: an implementation of `ballista_flight_sql::Authenticator` (Basic credentials in the handshake → token) and an axum middleware (Basic or Bearer). Both adapters resolve to the same `SessionInfo`, which is how one token works on both protocols.
- **Argon2id cost.** Verifying an Argon2id hash takes tens of milliseconds by design. Basic-authenticated HTTP clients (`curl -u`, the browser prompt for `/ui`) present credentials on every request, so `octopus-auth` keeps a small cache of recently verified credentials (key: SHA-256 of `user:password`, value: expiry; TTL a few minutes, bounded size) and bounds concurrent verifications with a semaphore so that a flood of wrong passwords degrades login latency rather than starving query threads. Token clients never hit Argon2id after login.
- One Ballista session per token. The `SessionBuilder` (`octopus-session`) creates a `SessionState` carrying `octopus.user`, `octopus.role`, `octopus.query_timeout`, the shared catalog provider, the storage registry, and the combined codecs.
- **HTTP sessions.** `POST /v1/login` with Basic credentials returns a token; token clients get a private session exactly like Flight SQL clients. A request that carries Basic credentials instead of a token is served from an *implicit session*: one per username, created on first use, idle-expired like any other, so `curl -u` works without a login step. The `session` object in a `POST /v1/statement` body applies `SET`-style options to that statement only.
- **Ownership.** Two different scopes, deliberately: *session* state (`SET` options, current schema, prepared statements, Flight result tickets) is private to the session; *statements* (HTTP handles and jobs) are owned by the **user**. A user may fetch, list, or cancel their own statements from any of their sessions; admins may do so for everyone. This is what makes the ticket-replay test per-session and the reader-cancel test per-user.
- Role checks live in `octopus-session` for DDL (statement inspection) and in `octopus-gateway` for HTTP routes.
- **Attribution.** Every Ballista job carries the `session_id` it was submitted under, and our `TokenStore` maps `session_id → user`. That join is the source of truth for the `user` and `protocol` fields in `/api` and `/v1/statements` (D11): no hook into `BallistaFlightSqlService` is needed to learn which user submitted a Flight SQL job. The gateway additionally keeps `StatementHandle`s for HTTP statements (`job_id`, `sql`, cursor), because HTTP needs paging state that Flight SQL does not.
- Ticket binding (*access-control*): tickets handed to clients are wrapped by us: `{ session_id, inner_ticket }` encrypted/MAC'd with a key generated at scheduler start (tickets are not meant to survive a restart; a restart fails all in-flight queries anyway); `DoGet` on the client port unwraps, checks the session, and forwards only to executors present in the scheduler's executor registry. Whether this can be done entirely in our wrapper or needs an upstream hook depends on how much of the ticket path is public; see *D12-c*.

*Alternatives:* a reverse proxy for authentication (rejected: adds a component and still leaves tickets unverified); JWT (deferred: opaque tokens are simpler and revocable; JWT/OIDC can be a later authenticator).

### D7. HTTP gateway calls the backend in-process

`octopus-gateway` is an axum router inside the scheduler process. It does **not** speak Flight SQL to itself; it calls the same `QueryBackend`/session machinery the Flight SQL service uses. Statement lifecycle:

1. `POST /v1/statement` → **parse synchronously** (a syntax error is HTTP 400 and creates nothing), then create `StatementHandle { id, session, state }` and plan and submit **asynchronously**, returning 202 with `nextUri` at once. Planning may list S3 prefixes or load a Delta log, so planning errors (unknown table, type error) surface as state `FAILED` on the first fetch, not as a 400.
2. `GET /v1/statement/{id}/{page}` → if the job is not finished, return current state with no rows and a `nextUri` pointing at the **same** page number (clients poll it); once finished, stream result partitions in order, slicing into pages of `http.page_rows` rows; JSON encoding per the spec, or Arrow IPC when requested. Pages are addressed by sequence number. **Retention:** results are not buffered whole in the scheduler; the handle keeps a cursor into the result stream plus the last served page, so re-fetching the current page (a retry) is idempotent, fetching the next page advances, and fetching an older page returns HTTP 410 Gone. Memory per handle is bounded by one page.
3. `DELETE` cancels via the backend; an idle sweeper cancels and drops handles not touched for `http.statement_idle_timeout`.

In staged mode the result partitions live on executors until Ballista's job clean-up removes them (executor `job_data_ttl_seconds`). A client that pages slower than that would get fetch errors, so `octopus-config` validates `http.statement_idle_timeout < executor job data TTL` and the operations guide states the relation.

Catalog endpoints call `octopus-catalog` directly, applying the same role checks as DDL. The Ballista REST API router is mounted under `/api` behind the auth middleware and is **admin-only** (it exposes cancel for any job and cluster internals); the gateway wraps `/api/jobs` and `/api/job/{id}` to add `user` and `protocol` resolved through the session → user mapping (D6), and adds `/api/history` (D11). `/metrics`, `/healthz`, `/readyz` are mounted without auth; `/metrics` carries counters and timings only, never SQL text or user names. OpenAPI is generated with `utoipa` from the handler types.

The monitoring UI is Ballista's Web TUI (a WebAssembly bundle built from `ballista-cli` with the `web` feature), **served by the gateway itself** at `/ui` so it is same-origin with `/api`; the browser's Basic-auth prompt (`WWW-Authenticate: Basic` on 401) supplies admin credentials to both. The hosted copy at nightlies.apache.org is not used: it cannot authenticate against us.

*Alternative:* Trino's exact HTTP protocol (rejected: it would promise compatibility with Trino clients we cannot fully honor; a clean, documented API is better for v1).

### D8. Delta Lake wiring

`deltalake` with features `datafusion`, `s3`. In `octopus-catalog`, a Delta `TableDef` becomes `DeltaTableProvider` built from `DeltaTable::load_with_version` (latest, or the version pinned in the table's `OPTIONS (version = 'N')`). **Time travel in v1 is per registration, not per query:** DataFusion's parser has no `FOR VERSION AS OF`, so per-query time travel would mean statement rewriting; an admin instead registers `events_v3 ... OPTIONS (version = '3')`. Per-query syntax is deferred. Plan serialization: our `OctopusLogicalCodec`/`OctopusPhysicalCodec` try the Delta codecs first and fall back to Ballista's default codec, installed on **both** scheduler and executor through `override_*_codec`. The executor needs the same delta-rs version and the same storage credentials: the physical codec on the executor rebuilds the Delta log store from the table URI plus our `[storage.s3]` options, so the codec is constructed with those options, not with DataFusion's registry alone. File lists are resolved on the scheduler and travel inside the serialized scan; whether the executor-side decode still opens the log (a `DeltaTable` load) is verified in task 9.2 and, if it does, documented as a known cost rather than hidden.

*Alternative:* converting Delta to a `ListingTable` over the live file list (rejected: loses deletion vectors, column mapping, and per-file statistics).

### D9. Execution mode and planner defaults

Staged mode stays the default (AQE on, retries on). Pipelined is opt-in per session via `SET ballista.execution.mode = 'pipelined'`; the scheduler runs with push-staged scheduling so pipelined jobs are accepted. We expose `octopus.query_timeout` as our own config extension and enforce it in the backend by cancelling the job. No other planner tuning in v1.

### D10. Configuration

One TOML per process, parsed with `serde` into typed structs in `octopus-config`, `deny_unknown_fields`, environment override via `OCTOPUS_` prefix with `_`-separated path (`figment` or hand-written layering, whichever keeps the code smaller). Secrets are `SecretString` (redacted `Debug`). The scheduler config contains `[cluster]`, `[flight_sql]`, `[http]`, `[storage.s3]`, `[catalog] path`, `[auth] idle_timeout`, `[[auth.users]]`, `[history] event_log_dir`, `[logging]`. The executor config contains `[cluster] scheduler_url`, `bind_*`, `vcores`, `memory_pool_fraction|size`, `work_dir`, `[storage.s3]`, `[logging]`.

### D11. Observability

Reuse Ballista's REST API, its job-level Prometheus metrics (`prometheus-metrics` feature on the scheduler), event-log writing (`event_log_dir`), the executor's existing health server (`/healthz`, `/readyz` on `bind_health_port`), executor and scheduler `--id`, and `min_ready_executors`.

**Per-executor metrics are ours.** Ballista exports no executor-labelled series (see Context), so `octopus-scheduler` derives them itself from the task status updates the scheduler already receives (`UpdateTaskStatus`: executor id, task timings, shuffle bytes written) and from the executor registry (active executors), and registers them in the same Prometheus registry: `octopus_executor_tasks_running{executor}`, `octopus_executor_task_seconds_total{executor}`, `octopus_executor_shuffle_bytes_total{executor}`, `octopus_executors_active`. **Metrics are scraped from the scheduler's `/metrics` only**; executors expose probes but no Prometheus endpoint of their own in v1 (adding one later is additive). The hook that observes task status updates must be a public extension point or a thin wrapper around the scheduler's gRPC server (the same server we assemble for the cluster-port interceptor, D3); if neither works it becomes upstream item *D12-e*.

**History is served by the gateway, not by a third process.** Ballista's history server is a separate process with its own UI and no authentication, and the reference stand has no slot for it. Instead the gateway reads the JSON Lines event log that the scheduler writes and exposes `GET /api/history` (admin-only, paged, filter by user and state) and `GET /api/history/{job_id}` (summary, plan, per-stage metrics). A retention sweeper deletes event-log files older than `[history] retention` on a timer, since Ballista does not prune the log. The Web TUI does not know this route; history is browsed through the API or `curl` in v1, and `docs/acceptance-v1.md` checks it that way.

User and protocol attribution comes from the session → user mapping (D6), not from Ballista. Logging is `tracing` with a JSON or pretty formatter chosen in config.

### D12. Upstream items (each requires owner approval before any PR)

| Id | Gap | Our fallback until merged |
|----|-----|---------------------------|
| a | Flight SQL service mountable on a separate port with a public `QueryBackend` impl | pinned branch exposing the impl |
| b | `PollFlightInfo` and `CancelFlightInfo`/`CancelQuery` in `ballista-flight-sql` | pinned branch; HTTP gateway already has async + cancel independently |
| c | Hook to validate result-ticket executor addresses against the registry / bind tickets to sessions | our wrapping `DoGet` on the client port (D6) if the inner ticket path is public |
| d | Prepared-statement parameter binding (`DoPutPreparedStatementQuery`) | pinned branch |
| e | (only if needed) an observer hook for task status updates to derive per-executor metrics (D11) | pinned branch |
| f | (only if needed) assembling the cluster-port gRPC server with our interceptor from public items | pinned branch |

Everything else in this change is built from released crates through public extension points (names verified against `apache/datafusion-ballista` `main` on 2026-11-11): `override_session_builder`, `override_config_producer`, `override_logical_codec`, `override_physical_codec`, `override_flight_sql_authenticator`, `override_create_grpc_client_endpoint` (reserved for TLS later), `advertise_flight_endpoint`, `min_ready_executors`, `event_log_dir`, `scheduler_id`/`executor_id`, the executor health server, `ExecutorProcessConfig` runtime producer, and the public `BallistaFlightSqlService`/`QueryBackend`/`Authenticator` types.

**Acceptance gate for upstream items (owner decision, 2026-11-06):** v1 is complete when a–d (and e, f if needed) work on the pinned branch and the owner has reviewed the diffs; upstream merge is pursued but is not a v1 exit criterion.

**Upstream process (owner requirement: strict control).** For each item, before any code is written for upstream:
1. Research demand: find the existing Ballista issue or discussion (e.g. [#2298](https://github.com/apache/datafusion-ballista/issues/2298) tracks the Flight SQL gaps), check the roadmap, and summarize whether the maintainers want the feature and in what shape.
2. Present to the owner: the gap, evidence of upstream demand, the proposed approach, and the alternative of keeping the change private on the pinned branch. The owner decides whether to pursue upstream at all.
3. If approved: open or comment on the upstream issue first to align with maintainers, implement on the pinned branch, have the owner review the diff, then open the PR.
4. Items the maintainers do not want stay on the pinned branch as a documented local patch (`docs/upstream-patches.md`), rebased on each Ballista release.

### D13. Testing strategy

- Unit tests in each crate (catalog store, DDL interception, config layering, token store, JSON encoding, codec round-trips).
- Integration tests in `tests/integration` run against the Compose stand: they talk Flight SQL (Rust `arrow-flight` client) and HTTP (`reqwest`). A `make stand-up` / `stand-down` wraps Compose. TPC-H SF1 Parquet is generated once by a small Rust helper (DataFusion's `tpchgen` crate) into MinIO; Delta copies of all eight tables are written with delta-rs; reference answers come from single-node DataFusion over the same Parquet files, computed in the harness and cached.
- Fault tests kill an executor container mid-query (staged: must succeed; pipelined: must fail cleanly).
- Client recipes in `docs/clients.md` are executed manually once per release for DataGrip; ADBC and curl recipes run in CI.

### D14. Code comprehensibility rules

- No procedural macros of our own; derive macros from `serde`, `clap`, `utoipa`, `thiserror` only.
- Every use of a Ballista or DataFusion extension point is documented in `docs/architecture.md` with the trait name and why we implement it.
- Each decision above becomes an ADR; changing a decision means a new ADR, not an edit.
- Public items have doc comments explaining intent, not just signature.

## Risks / Trade-offs

- [Ballista majors every ~2 months, strict version coupling] → pin exact versions in the workspace; one `chore: bump ballista` change per release with the Compose stand as the gate.
- [Pipelined mode is experimental] → staged is default; pipelined is documented as opt-in with its failure semantics.
- [Flight SQL gaps need upstream review time] → gateway delivers async submit/cancel without upstream; pinned branch unblocks Flight SQL; the owner decides what to upstream and when.
- [Hash join does not spill] → Ballista's default (`prefer_hash_join = false`, broadcast threshold) stays; documented in operations guide; memory errors are per-query, not per-process.
- [DataGrip's Flight SQL JDBC driver requires `useEncryption=false` without TLS] → documented; TLS termination is an open question below.
- [delta-rs and Ballista may disagree on DataFusion patch versions] → both pinned in one `Cargo.lock`; CI builds fail loudly on mismatch.
- [SQLite catalog is single-writer] → fine for one scheduler; the trait allows Postgres later.
- [Result traffic through the scheduler process] → acceptable at v1 scale; `ballista-result-service` is the documented scale-out path.
- [Web TUI bundle must be rebuilt per Ballista release] → built in CI from the pinned Ballista version; a stale bundle only affects the UI, not queries.
- [Implicit per-user HTTP sessions share `SET` state between a user's concurrent Basic-auth clients] → documented; clients needing isolation use `/v1/login` tokens.
- [Argon2id verification per Basic request is slow and a cheap DoS lever] → verified-credential cache and a verification semaphore (D6); the operations guide recommends tokens for services.
- [Per-executor metrics and history are our code, not Ballista's] → both are small, read-only consumers of data the scheduler already has (task status updates, event log); they add no new process and no new protocol.
- [HTTP result paging depends on executor job-data retention] → config validation ties `http.statement_idle_timeout` to the executor job data TTL (D7).

## Migration Plan

Greenfield: no migration. Deployment is `docker compose up` on the reference stand. Rollback is re-deploying the previous image tag of scheduler and executor **together** (Ballista protocol version check enforces this).

## Open Questions

- TLS: terminate at a proxy in front of the client ports, or native TLS in the scheduler? Does not change specs or tasks for v1 (plaintext on the stand); decide before any non-local deployment.
- Whether pipelined mode becomes the default for short interactive queries once it leaves experimental status upstream.
- Whether the Web TUI should learn the `/api/history` route (an upstream UI change) or a small history page of our own is preferable; v1 browses history through the API only.
