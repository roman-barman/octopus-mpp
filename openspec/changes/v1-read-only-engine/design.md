# Design

## Context

See `proposal.md` for motivation. This section records only the facts about the starting point that shape the design.

- **Greenfield repository.** Nothing exists yet except OpenSpec scaffolding.
- **Ballista 55 (DataFusion 55, Arrow 59)** is the base. Observed state of `apache/datafusion-ballista` at `main` on 2026-11-06:
  - Crates: `ballista-core`, `ballista-scheduler`, `ballista-executor`, `ballista-client`, `ballista-flight-sql`, `ballista-history`, `ballista-result-service`, `ballista-api-types`.
  - Scheduler extension points (`SchedulerConfig`): `override_session_builder`, `override_config_producer`, `override_logical_codec`, `override_physical_codec`, `override_flight_sql_authenticator`, `adaptive_rules`, `job_id_generator`. Executor extension points (`ExecutorProcessConfig`): function registry, runtime producer, config producer, codecs.
  - Flight SQL frontend exists (`BallistaFlightSqlService` over a `QueryBackend` trait, pluggable `Authenticator`) but: is mounted on the **same gRPC port** as the executor-facing scheduler API; has **no** `PollFlightInfo`, **no** cancellation, **no** parameter binding; result tickets carry executor addresses that are **not validated**; unauthenticated clients share one anonymous session; sessions and their catalogs are in-memory and expire after 30 minutes idle.
  - Cluster state has one backend: in-memory. Catalog state per session only.
  - REST monitoring API (`/api/*`, OpenAPI), Web TUI (hosted, talks to REST via CORS), history server (JSON Lines event log), Prometheus metrics, `/healthz`, `/readyz`, graceful shutdown, protocol-version check all exist.
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
```

One crate per responsibility, no crate depends on a binary crate, and the two binaries contain only wiring. This is the main instrument for the "understand all the code" goal.

*Alternative:* a single crate with modules (rejected: compile times and blurred boundaries as soon as the gateway and catalog grow).

### D3. Two binaries, three scheduler ports

The scheduler process serves:

| Port (config key)            | Protocol                          | Audience          |
|------------------------------|-----------------------------------|-------------------|
| `cluster.bind_port` (50050)  | Ballista gRPC (executor API)      | executors only    |
| `flight_sql.bind_port` (50060) | Arrow Flight SQL (gRPC)         | clients           |
| `http.bind_port` (8080)      | HTTP: `/v1/*`, `/api/*`, `/metrics`, probes | clients, operators |

Ballista mounts Flight SQL on the cluster port. We instead construct `BallistaFlightSqlService` ourselves on a separate tonic server, backed by the scheduler's `QueryBackend` implementation. If that implementation is not reachable through the public API, the fix is an upstream item (*D12-a*) and, until then, lives on the pinned branch. The cluster port is never published outside the cluster network; the Compose file only publishes the two client ports.

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

An `OctopusCatalogProvider` implements DataFusion's `CatalogProvider`/`SchemaProvider` over the store and builds `TableProvider`s lazily: `ListingTable` (DataFusion) for Parquet with the persisted schema, `DeltaTableProvider` (delta-rs) for Delta, loading the latest snapshot at planning time. Providers are cached per table with a short TTL (default 30 s) and invalidated on DDL. Because the catalog provider is shared, every session sees the same tables immediately.

DDL is intercepted **before** DataFusion executes it: `octopus-session` inspects the parsed statement; `CREATE EXTERNAL TABLE`, `DROP TABLE`, `CREATE/DROP SCHEMA`, `ALTER TABLE ... REFRESH SCHEMA` are handled by `octopus-catalog` (schema inference, store write, cache invalidation) and never reach Ballista's per-session in-memory catalog. Read statements pass through untouched.

*Alternatives:* JSON file (rejected: no transactions, awkward concurrent writes from HTTP and SQL); embedded KV such as `redb`/`sled` (rejected: SQLite is better understood and inspectable with standard tools); Postgres (deferred: becomes relevant only with multiple schedulers; the trait makes it a drop-in).

### D5. Object storage configuration

`octopus-storage` builds an `ObjectStoreRegistry` from `[storage.s3]` in the process configuration (endpoint, region, access key, secret key, session token, `path_style`, `allow_http`) and registers `file://` for local development. The same registry is installed in the scheduler's `RuntimeEnv` (planning, schema inference, Delta log reads) and in the executor's (scans). SQL `SET` of storage credentials is rejected (we do not install Ballista's `S3Options` config extension). delta-rs receives the same credentials through its storage options map so Delta log reads use the same endpoint.

*Alternative:* Ballista's `CustomObjectStoreRegistry` driven by `SET` (rejected: credentials in SQL are a security and auditing problem and are per-session, not per-cluster).

### D6. Sessions and authentication

- `octopus-auth` holds `Users` (from config: name, Argon2id hash, role), a `TokenStore` (random 256-bit opaque tokens → `SessionInfo { user, role, session_id, last_seen }`, idle TTL from config), and two adapters: an implementation of `ballista_flight_sql::Authenticator` (Basic credentials in the handshake → token) and an axum middleware (Basic or Bearer). Both adapters resolve to the same `SessionInfo`, which is how one token works on both protocols.
- One Ballista session per token. The `SessionBuilder` (`octopus-session`) creates a `SessionState` carrying `octopus.user`, `octopus.role`, `octopus.query_timeout`, the shared catalog provider, the storage registry, and the combined codecs.
- **HTTP sessions.** `POST /v1/login` with Basic credentials returns a token; token clients get a private session exactly like Flight SQL clients. A request that carries Basic credentials instead of a token is served from an *implicit session*: one per username, created on first use, idle-expired like any other, so `curl -u` works without a login step. The `session` object in a `POST /v1/statement` body applies `SET`-style options to that statement only.
- **Ownership.** Two different scopes, deliberately: *session* state (`SET` options, current schema, prepared statements, Flight result tickets) is private to the session; *statements* (HTTP handles and jobs) are owned by the **user**. A user may fetch, list, or cancel their own statements from any of their sessions; admins may do so for everyone. This is what makes the ticket-replay test per-session and the reader-cancel test per-user.
- Role checks live in `octopus-session` for DDL (statement inspection) and in `octopus-gateway` for HTTP routes. The gateway keeps a `job_id → (user, protocol, sql)` registry for every job it or the Flight SQL service submits; this is the source of truth for attribution in `/api` and `/v1/statements` (see D11).
- Ticket binding (*access-control*): tickets handed to clients are wrapped by us: `{ session_id, inner_ticket }` encrypted/MAC'd with a process key; `DoGet` on the client port unwraps, checks the session, and forwards only to executors present in the scheduler's executor registry. Whether this can be done entirely in our wrapper or needs an upstream hook depends on how much of the ticket path is public; see *D12-c*.

*Alternatives:* a reverse proxy for authentication (rejected: adds a component and still leaves tickets unverified); JWT (deferred: opaque tokens are simpler and revocable; JWT/OIDC can be a later authenticator).

### D7. HTTP gateway calls the backend in-process

`octopus-gateway` is an axum router inside the scheduler process. It does **not** speak Flight SQL to itself; it calls the same `QueryBackend`/session machinery the Flight SQL service uses. Statement lifecycle:

1. `POST /v1/statement` → create `StatementHandle { id, session, state }`, submit the plan asynchronously, return 202 with `nextUri`.
2. `GET /v1/statement/{id}/{page}` → if the job is not finished, return current state with no rows (clients poll `nextUri`); once finished, stream result partitions in order, slicing into pages of `http.page_rows` rows; JSON encoding per the spec, or Arrow IPC when requested. Pages are addressed by sequence number. **Retention:** results are not buffered whole in the scheduler; the handle keeps a cursor into the result stream plus the last served page, so re-fetching the current page (a retry) is idempotent, fetching the next page advances, and fetching an older page returns HTTP 410 Gone. Memory per handle is bounded by one page.
3. `DELETE` cancels via the backend; an idle sweeper cancels and drops handles not touched for `http.statement_idle_timeout`.

Catalog endpoints call `octopus-catalog` directly, applying the same role checks as DDL. The Ballista REST API router is mounted under `/api` behind the auth middleware and is **admin-only** (it exposes cancel for any job and cluster internals); the gateway wraps `/api/jobs` and `/api/job/{id}` to add `user` and `protocol` from its job registry. `/metrics`, `/healthz`, `/readyz` are mounted without auth. OpenAPI is generated with `utoipa` from the handler types.

The monitoring UI is Ballista's Web TUI (a WebAssembly bundle built from `ballista-cli` with the `web` feature), **served by the gateway itself** at `/ui` so it is same-origin with `/api`; the browser's Basic-auth prompt (`WWW-Authenticate: Basic` on 401) supplies admin credentials to both. The hosted copy at nightlies.apache.org is not used: it cannot authenticate against us.

*Alternative:* Trino's exact HTTP protocol (rejected: it would promise compatibility with Trino clients we cannot fully honor; a clean, documented API is better for v1).

### D8. Delta Lake wiring

`deltalake` with features `datafusion`, `s3`. In `octopus-catalog`, a Delta `TableDef` becomes `DeltaTableProvider` built from `DeltaTable::load_with_version` (latest, or the version pinned in the table's `OPTIONS (version = 'N')`). **Time travel in v1 is per registration, not per query:** DataFusion's parser has no `FOR VERSION AS OF`, so per-query time travel would mean statement rewriting; an admin instead registers `events_v3 ... OPTIONS (version = '3')`. Per-query syntax is deferred. Plan serialization: our `OctopusLogicalCodec`/`OctopusPhysicalCodec` try the Delta codecs first and fall back to Ballista's default codec, installed on **both** scheduler and executor through `override_*_codec`. The executor needs the same delta-rs version and the same storage registry; file lists are resolved on the scheduler and travel inside the serialized scan, which is what makes distributed Delta scans work without executors touching the log.

*Alternative:* converting Delta to a `ListingTable` over the live file list (rejected: loses deletion vectors, column mapping, and per-file statistics).

### D9. Execution mode and planner defaults

Staged mode stays the default (AQE on, retries on). Pipelined is opt-in per session via `SET ballista.execution.mode = 'pipelined'`; the scheduler runs with push-staged scheduling so pipelined jobs are accepted. We expose `octopus.query_timeout` as our own config extension and enforce it in the backend by cancelling the job. No other planner tuning in v1.

### D10. Configuration

One TOML per process, parsed with `serde` into typed structs in `octopus-config`, `deny_unknown_fields`, environment override via `OCTOPUS_` prefix with `_`-separated path (`figment` or hand-written layering, whichever keeps the code smaller). Secrets are `SecretString` (redacted `Debug`). The scheduler config contains `[cluster]`, `[flight_sql]`, `[http]`, `[storage.s3]`, `[catalog] path`, `[auth] idle_timeout`, `[[auth.users]]`, `[history] event_log_dir`, `[logging]`. The executor config contains `[cluster] scheduler_url`, `bind_*`, `vcores`, `memory_pool_fraction|size`, `work_dir`, `[storage.s3]`, `[logging]`.

### D11. Observability

Reuse Ballista's REST API, Prometheus metrics (`prometheus-metrics` feature on the scheduler, which already aggregates executor task and shuffle metrics with executor labels), event-log history (`--event-log-dir` equivalent), the executor's existing health server (`/healthz`, `/readyz` on `bind_health_port`), executor and scheduler `--id`, and `min_ready_executors`. **Metrics are scraped from the scheduler's `/metrics` only**, with per-executor labels; executors expose probes but no Prometheus endpoint of their own in v1 (adding one later is additive). The history server is run as a `octopus-scheduler history` subcommand so there is no third binary to learn. User and protocol attribution comes from the gateway's job registry (D7), not from Ballista. Logging is `tracing` with a JSON or pretty formatter chosen in config.

### D12. Upstream items (each requires owner approval before any PR)

| Id | Gap | Our fallback until merged |
|----|-----|---------------------------|
| a | Flight SQL service mountable on a separate port with a public `QueryBackend` impl | pinned branch exposing the impl |
| b | `PollFlightInfo` and `CancelFlightInfo`/`CancelQuery` in `ballista-flight-sql` | pinned branch; HTTP gateway already has async + cancel independently |
| c | Hook to validate result-ticket executor addresses against the registry / bind tickets to sessions | our wrapping `DoGet` on the client port (D6) if the inner ticket path is public |
| d | Prepared-statement parameter binding (`DoPutPreparedStatementQuery`) | pinned branch |
| f | (only if needed) assembling the cluster-port gRPC server with our interceptor from public items | pinned branch |

Everything else in this change is built from released crates through public extension points: `override_session_builder`, `override_config_producer`, `override_logical_codec`, `override_physical_codec`, `override_flight_sql_authenticator`, `advertise_flight_endpoint`, `min_ready_executors`, `event_log_dir`, `scheduler_id`/`executor_id`, the executor health server, `ExecutorProcessConfig` runtime producer, and the public `BallistaFlightSqlService`/`QueryBackend` types.

**Acceptance gate for upstream items (owner decision, 2026-11-06):** v1 is complete when a–d (and f if needed) work on the pinned branch and the owner has reviewed the diffs; upstream merge is pursued but is not a v1 exit criterion.

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

## Migration Plan

Greenfield: no migration. Deployment is `docker compose up` on the reference stand. Rollback is re-deploying the previous image tag of scheduler and executor **together** (Ballista protocol version check enforces this).

## Open Questions

- TLS: terminate at a proxy in front of the client ports, or native TLS in the scheduler? Does not change specs or tasks for v1 (plaintext on the stand); decide before any non-local deployment.
- Whether pipelined mode becomes the default for short interactive queries once it leaves experimental status upstream.
- Whether the hosted Web TUI is acceptable long-term or a bundled copy is preferred for air-gapped stands (serving a static bundle is additive).
