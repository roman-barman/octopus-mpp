# Proposal

## Why

Trino-class MPP engines are heavy to run (JVM, external metastore, many knobs) and expensive in CPU and memory. Apache DataFusion Ballista now provides a mature Rust scheduler/executor core (version 55, adaptive query execution, experimental Trino-style pipelined execution, an Arrow Flight SQL frontend) but is a toolkit, not a product: it has no persistent catalog, no authentication, and known gaps in its Flight SQL frontend. octopus-mpp turns that toolkit into a self-contained, read-only distributed SQL engine for Parquet and Delta Lake data in S3-compatible storage, with Trino-level functionality for analysts and services, and a codebase small and explicit enough that one person can understand all of it.

## What Changes

- A new Cargo workspace with two deployable processes, `octopus-scheduler` and `octopus-executor`, built on the Ballista crates as dependencies (no fork). Anything that must change inside Ballista is proposed upstream, with every upstream task and pull request agreed and reviewed by the project owner first; unmerged patches are consumed through a pinned git branch.
- A persistent, built-in table catalog (`catalog.schema.table`) managed through SQL DDL and HTTP, shared by all sessions and surviving restarts. No external metastore.
- Reading Parquet from S3-compatible storage (MinIO first), including Hive-style partitioned directories, with credentials from process configuration.
- Reading Delta Lake tables from the same storage, with table schema and file list taken from the Delta transaction log.
- An Arrow Flight SQL endpoint (gRPC) as the primary client protocol for JDBC (DataGrip), ADBC (Python), and other Arrow clients, completed with query cancellation, long-query polling, and bound parameters.
- A thin HTTP/JSON gateway for browsers, `curl`, and services, serving the same queries and catalog operations with paged JSON or Arrow IPC results.
- Authentication (username/password → bearer token) for every client entry point, per-user sessions, a minimal admin/reader role split, and a strict separation between client-facing ports and the cluster-internal scheduler/executor ports.
- Operations: single TOML configuration per process, health/readiness probes, Prometheus metrics, query history, and the Ballista REST API and Web TUI as the v1 monitoring UI. A Docker Compose stand with MinIO, one scheduler, and two executors as the reference test environment.
- A correctness harness: TPC-H (scale factor 1) generated into MinIO as Parquet plus Delta copies of all eight tables, with all 22 queries verified against reference results on both formats.
- Explicitly **not** a supported client: Ballista's native Rust/Python client protocol. Its RPCs are blocked on the cluster port; clients use Flight SQL or HTTP.

Explicitly **not** in this version: writes of any kind (`INSERT`, `CTAS`, `UPDATE`, `DELETE`, `MERGE`), Hive Metastore / Glue adapters, multi-scheduler high availability, query queues and resource groups, data caching, performance tuning against Trino, a custom web UI, Kubernetes manifests of our own, and sources other than Parquet and Delta Lake on S3-compatible storage.

## Capabilities

### New Capabilities
- `cluster-operations`: how scheduler and executor processes start, are configured, report health, shut down, and are run together on the reference Docker Compose stand.
- `query-execution`: distributed execution of read-only SQL across executors: supported SQL surface, execution modes, memory limits, failure behavior, and result correctness.
- `table-catalog`: the built-in persistent catalog of catalogs, schemas, and tables; DDL for registering and dropping tables; introspection through `information_schema` and `SHOW`/`DESCRIBE`.
- `parquet-s3-source`: reading Parquet tables from S3-compatible object storage, including Hive-partitioned layouts and partition pruning.
- `delta-lake-source`: reading Delta Lake tables from S3-compatible object storage using the Delta transaction log.
- `flight-sql-frontend`: the Arrow Flight SQL endpoint: statements, prepared statements with parameters, catalog metadata, cancellation, polling, and result streaming.
- `http-gateway`: the HTTP/JSON API for submitting queries, fetching paged results (JSON or Arrow IPC), cancelling, and managing the catalog.
- `access-control`: authentication, tokens, sessions, roles, and network exposure rules for client-facing versus cluster-internal endpoints.
- `observability`: query monitoring, history, metrics, logging, and `EXPLAIN` output available to operators.

### Modified Capabilities
<!-- none: greenfield project -->

## Impact

- New repository content: Cargo workspace, `deploy/` Docker Compose files, `docs/` architecture and ADRs, `tests/` integration harness.
- External dependencies: `ballista-scheduler`, `ballista-executor`, `ballista-core`, `ballista-flight-sql` (55.x, DataFusion 55, Arrow 59), `deltalake` 2.x with the `datafusion` feature, `object_store` with the `aws` feature, `axum`, `tonic`, `rusqlite`. Ballista moves a major version with every DataFusion major; the project follows that cadence and upgrades scheduler, executor, and client-facing crates together.
- Upstream work (each item agreed and reviewed by the project owner before any pull request is opened): Flight SQL `PollFlightInfo` and `CancelQuery`, prepared-statement parameter binding, validation of result-fetch tickets against registered executors, serving Flight SQL on a port separate from the executor-facing scheduler port, and, if needed, assembling the cluster-port gRPC server with an interceptor. Until merged, each lives on a pinned branch; v1 does not wait for upstream merges.
- Clients: DataGrip via the Arrow Flight SQL JDBC driver, Python via `adbc-driver-flightsql`, `curl` via the HTTP gateway. All are independent of the cluster's Ballista version.
