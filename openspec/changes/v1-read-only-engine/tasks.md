# Tasks

Each task names how it is verified. Tasks marked **[upstream]** touch Ballista internals and MUST be agreed with the project owner (scope, approach, diff) before any pull request is opened; until merged they live on the pinned branch (design D12).

## 1. Repository bootstrap

- [ ] 1.1 Initialize git, Cargo workspace, `rust-toolchain.toml`, `.gitignore`, `README.md`; verify `cargo build` of an empty workspace succeeds
- [ ] 1.2 Create crates `octopus-config`, `octopus-storage`, `octopus-catalog`, `octopus-auth`, `octopus-session`, `octopus-gateway`, `octopus-scheduler`, `octopus-executor` with README stubs stating each crate's single responsibility; verify `cargo build --workspace`
- [ ] 1.3 Pin workspace dependencies (ballista 55.x crates, datafusion 55, arrow 59, deltalake 2.x, object_store, axum, tonic, rusqlite, tracing); verify `cargo tree` shows one DataFusion and one Arrow version
- [ ] 1.4 Add CI (GitHub Actions): fmt, clippy `-D warnings`, unit tests; verify the workflow passes on the bootstrap commit
- [ ] 1.5 Write `docs/architecture.md` skeleton (components, ports table, query lifecycle placeholder) and `docs/adr/0001-ballista-as-dependency.md`, `0002-workspace-layout.md`; verify they are linked from README

## 2. Configuration and storage

- [ ] 2.1 Implement `octopus-config`: scheduler and executor TOML structs with `deny_unknown_fields`, `SecretString`, env overrides (`OCTOPUS_*`), validation errors naming the key; verify unit tests for file+env layering, unknown-key rejection, and redaction in `Debug`
- [ ] 2.2 Implement `octopus-storage`: `ObjectStoreRegistry` building `s3://` (MinIO options: endpoint, path-style, allow-http, credentials) and `file://` stores from config; verify a unit test reads a local file and an ignored-by-default test lists a MinIO bucket
- [ ] 2.3 Write `docs/operations.md` configuration reference generated from the config structs' doc comments; verify every key in the example TOML files is documented
- [ ] 2.4 Add ADR `0003-config-and-storage.md`; verify linked from `docs/architecture.md`

## 3. Cluster processes and Compose stand

- [ ] 3.1 Implement `octopus-executor` binary: load config, build `ExecutorProcessConfig` with our storage registry (runtime producer) and vcores/memory settings, start Ballista executor; verify it registers against a plain `ballista-scheduler` locally
- [ ] 3.2 Implement `octopus-scheduler` binary (cluster port only for now): load config, build `SchedulerConfig` (push-staged policy, min ready executors, event log dir), start; verify `/healthz` and `/readyz` behave per `cluster-operations` with 0 and 1 executors
- [ ] 3.3 Implement `--standalone` flag running scheduler and executor in one process with Ballista's built-in Flight SQL enabled; verify a Rust test runs `SELECT 1` through an `arrow-flight` Flight SQL client against it
- [ ] 3.4 Implement graceful shutdown on SIGTERM for both binaries with configured grace period; verify an integration test sends SIGTERM to an executor mid-query and the query completes on the other executor (staged mode)
- [ ] 3.5 Create `deploy/compose` with MinIO (+ bucket bootstrap job), one scheduler, two executors, `scheduler.toml`, `executor.toml`, publishing only client ports, plus a `compose.dev.yml` override that temporarily publishes the cluster port for Phase 3–5 smoke tests (removed in Phase 6); verify `docker compose up` reaches `/readyz` 200 with two executors in under two minutes
- [ ] 3.6 Add `tests/integration` harness: Compose up/down helpers, MinIO upload helper, Flight SQL (`arrow-flight`) and HTTP (`reqwest`) client helpers; verify a smoke test uploads a Parquet file and runs `SELECT count(*)` through Ballista's built-in Flight SQL on the dev-published cluster port
- [ ] 3.7 Document running the stand in `docs/operations.md`; verify the documented commands work as written

## 4. Catalog

- [ ] 4.1 Define `CatalogStore` trait and `TableDef`/`SchemaDef` types; implement `SqliteCatalogStore` (WAL, migrations table); verify unit tests for create/list/drop schema and table, cascade rules, persistence across reopen
- [ ] 4.2 Implement `OctopusCatalogProvider` + `SchemaProvider` over the store with lazy `TableProvider` creation and TTL cache; verify a unit test resolves a registered Parquet table through a DataFusion `SessionContext`
- [ ] 4.3 Implement Parquet schema inference for `CREATE EXTERNAL TABLE` (merge compatible schemas, fail on conflicts naming column and files) and `PARTITIONED BY` typed partition columns; verify unit tests with fixture files
- [ ] 4.4 Implement DDL interception in `octopus-session` (`CREATE/DROP SCHEMA`, `CREATE EXTERNAL TABLE`, `DROP TABLE`, `ALTER TABLE ... REFRESH SCHEMA`) routed to the catalog; verify unit tests that read statements pass through untouched and write statements are rejected as read-only
- [ ] 4.5 Implement `SessionBuilder` that installs the shared catalog provider, storage registry, Ballista functions/optimizer rules, `octopus.*` options, and default catalog/schema; wire into `SchedulerConfig::override_session_builder`; verify an integration test registers a table in one session and queries it in another
- [ ] 4.6 Verify `information_schema`, `SHOW CATALOGS/SCHEMAS/TABLES/COLUMNS`, `DESCRIBE`, `SET SCHEMA`/`USE` against the catalog; verify integration tests for each
- [ ] 4.7 Verify persistence: integration test registers tables, restarts the scheduler container, queries them
- [ ] 4.8 Write `docs/catalog.md` (naming, DDL reference, refresh semantics) and ADR `0004-builtin-catalog.md`; verify DDL examples in the doc run on the stand

## 5. Parquet on S3 and the TPC-H harness

- [ ] 5.1 Add TPC-H SF1 generation helper (Parquet into MinIO, `lineitem`/`orders` Hive-partitioned by date) to the harness; verify the eight tables register and `count(*)` matches TPC-H row counts
- [ ] 5.2 Implement reference-answer computation with single-node DataFusion and tolerant comparison; verify the comparison detects an injected wrong row
- [ ] 5.3 Run all 22 TPC-H queries through the cluster in staged mode; verify every result matches the reference
- [ ] 5.4 Run the suite in pipelined mode; verify every result matches, and document any query that needs more memory in `docs/operations.md`
- [ ] 5.5 Verify partition pruning and row-group pruning via `EXPLAIN ANALYZE` file/row-group counts in integration tests
- [ ] 5.6 Verify nested-type reading (struct/list/map fixture) and the credential-via-`SET` rejection in integration tests
- [ ] 5.7 Fault test: kill an executor container during a staged query and assert success; during a pipelined query and assert a clear failure; verify both in the integration suite

## 6. Authentication, sessions, and network boundaries

- [ ] 6.1 Implement `octopus-auth`: users from config with Argon2id hashes (reject plaintext), `hash-password` subcommand, `TokenStore` with idle TTL; verify unit tests for verify/expiry/revocation and plaintext rejection
- [ ] 6.2 Implement the `ballista_flight_sql::Authenticator` adapter (Basic → token, no anonymous); wire via `override_flight_sql_authenticator`; verify an integration test logs in with ADBC and a wrong password is rejected with `UNAUTHENTICATED`
- [ ] 6.3 Carry user and role into the session (`octopus.user`, `octopus.role`) and enforce `admin` for DDL; verify integration tests for reader-denied DDL and admin-allowed DDL
- [ ] 6.4 **[upstream a]** Serve Flight SQL on a dedicated port with the scheduler's `QueryBackend`; agree approach with owner, implement on pinned branch, wire in `octopus-scheduler`; verify executor RPCs are not served on the client port, remove `compose.dev.yml`, and verify the Compose stand publishes only client ports
- [ ] 6.4b Build the cluster-port gRPC server with an interceptor that rejects all non-executor RPCs (**[upstream f]** only if public items are insufficient); verify an integration test calling `ExecuteQuery` on the cluster port gets `PERMISSION_DENIED` while executors still register
- [ ] 6.5 **[upstream c]** Bind result tickets to sessions and restrict result fetches to registered executors (wrapper on our client port, or upstream hook); agree approach with owner; verify integration tests for ticket replay from another session and a forged executor address
- [ ] 6.6 Log authentication outcomes without secrets; verify a unit test on the log formatter and a manual check on the stand
- [ ] 6.7 Write `docs/security.md` (users, roles, ports, what is internal) and ADR `0005-auth-and-ports.md`; verify linked from architecture

## 7. Flight SQL completeness

- [ ] 7.1 Verify the catalog metadata commands (`GetCatalogs`, `GetDbSchemas`, `GetTables`, `GetTableTypes`, `GetSqlInfo`, `GetXdbcTypeInfo`) against our catalog with an ADBC integration test
- [ ] 7.2 Implement `octopus.query_timeout` enforcement by cancelling the Ballista job; verify an integration test times out a slow query
- [ ] 7.3 **[upstream b]** `PollFlightInfo` and `CancelFlightInfo`/`CancelQuery`, plus cancel-on-disconnect; agree approach with owner, implement on pinned branch; verify integration tests: poll until done, explicit cancel stops executor tasks within five seconds, disconnect cancels after idle timeout
- [ ] 7.4 **[upstream d]** Prepared-statement parameter binding; agree approach with owner, implement on pinned branch; verify ADBC test with a bound parameter and a wrong-count error
- [ ] 7.5 Verify error mapping (unknown table, planning error, execution error) to gRPC statuses without stack traces in integration tests
- [ ] 7.6 Write `docs/clients.md` with DataGrip (driver class, URL, `useEncryption=false`, credentials) and ADBC recipes; verify the ADBC recipe runs in CI and the DataGrip recipe manually (schema browser lists tables, query runs)

## 8. HTTP gateway

- [ ] 8.1 Implement axum router on the HTTP port with auth middleware (Bearer tokens and Basic → implicit per-user session, sharing `TokenStore`), `POST /v1/login`, unauthenticated `/healthz`, `/readyz`, `/metrics`; verify unit tests for 401, login, implicit-session reuse, and probe routes
- [ ] 8.2 Implement `POST /v1/statement` (async submit, 202 + `nextUri`, 400 on planning error), the user-owned `StatementHandle` registry (`job_id → user, protocol, sql`) with idle sweeper, and ownership checks (owner or admin); verify integration tests for submit, planning error, idle expiry, Basic-only fetch from a second connection, and 403 for another user
- [ ] 8.3 Implement paged `GET /v1/statement/{id}/{page}` with cursor semantics (current page re-fetch idempotent, older page → 410), JSON encoding per spec (64-bit ints, decimals, timestamps, binary, nested) and final-page `stats`; verify unit tests per type and an integration test paging TPC-H Q1 including a retried page and a 410
- [ ] 8.4 Implement Arrow IPC pages via `Accept` header; verify an integration test decodes the stream with `arrow-ipc` and compares to JSON rows
- [ ] 8.5 Implement `DELETE /v1/statement/{id}` and `GET /v1/statements` with role scoping; verify integration tests for cancel and reader/admin listing
- [ ] 8.6 Implement catalog endpoints with the same semantics and role checks as DDL; verify integration tests register/list/describe/refresh/drop a table over HTTP and see it via SQL
- [ ] 8.7 Generate OpenAPI with `utoipa` at `/v1/openapi.json`; verify it validates with an OpenAPI validator in CI
- [ ] 8.8 Mount Ballista REST `/api/*` behind admin-only auth, wrapping `/api/jobs` and `/api/job/{id}` to add `user` and `protocol` from the statement registry (covers Flight SQL-submitted jobs too); verify integration tests: admin sees `"user": "alice"` for a running query, reader gets 403
- [ ] 8.8b Build the Ballista Web TUI wasm bundle in CI from the pinned Ballista version and serve it at `/ui` behind the same auth; verify manually that the browser prompt authenticates and executors and queries render
- [ ] 8.9 Document the HTTP API with `curl` recipes in `docs/clients.md` and ADR `0006-http-gateway.md`; verify recipes run in CI

## 9. Delta Lake

- [ ] 9.1 Add `deltalake` dependency; implement Delta `TableDef` → `DeltaTableProvider` (latest version, or version pinned via `OPTIONS (version = 'N')`) in `octopus-catalog` with storage options from `[storage.s3]`; verify a unit test loads a local Delta fixture at latest and at a pinned version
- [ ] 9.2 Implement combined logical/physical codecs (Delta first, Ballista default fallback) and install on scheduler and executor; verify a codec round-trip unit test for a Delta scan plan
- [ ] 9.3 Write Delta copies of all eight TPC-H tables into MinIO in the harness (delta-rs writer), including one partitioned table and one with deletion vectors and column mapping; verify tables register by location and `DESCRIBE` matches the log schema
- [ ] 9.4 Run the 22 TPC-H queries over the Delta tables; verify results equal the Parquet results
- [ ] 9.5 Verify snapshot isolation (commit during a query), latest-version pickup, pinned-version registration, rejection of `FOR VERSION AS OF`, partition pruning from the log, and the "not a Delta table" / unsupported-feature errors in integration tests
- [ ] 9.6 Write `docs/delta.md` and ADR `0007-delta-lake.md`; verify examples run on the stand

## 10. Observability

- [ ] 10.1 Enable Prometheus metrics on the scheduler at `/metrics` (with per-executor labels); verify an integration test scrapes and finds the required metric families and an `executor="exec-1"` label
- [ ] 10.2 Enable event logging and implement the `octopus-scheduler history` subcommand; verify an integration test lists completed queries after a scheduler restart
- [ ] 10.3 Configure executor and scheduler ids from config (`id = "exec-1"`) and verify the monitoring API lists them by that id in an integration test
- [ ] 10.4 Configure structured logging (`tracing`, JSON/pretty, per-module levels) with query id in executor error logs; verify a unit test on the formatter and a stand check
- [ ] 10.5 Verify `EXPLAIN` and `EXPLAIN ANALYZE` output (stages, exchanges, per-stage metrics) in integration tests; document in `docs/clients.md`

## 11. Acceptance

- [ ] 11.1 Run the full integration suite on a clean Compose stand from a fresh clone; verify all tests pass in CI
- [ ] 11.2 Complete the manual acceptance checklist in `docs/acceptance-v1.md`: DataGrip login, schema browser, TPC-H query, cancel from DataGrip, Web TUI shows the query and history; record results in the file
- [ ] 11.3 Finish `docs/architecture.md` query lifecycle (client → auth → session → planner → scheduler → executors → results) with the ADR index; verify every Ballista/DataFusion extension point used in code is listed

## Workflow follow-up

- Archive the change after the owner's review; sync delta specs into `openspec/specs`.
- Open follow-up changes for: writes, Hive Metastore adapter, TLS, custom UI, performance benchmarking against Trino.
