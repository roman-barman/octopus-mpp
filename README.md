# octopus-mpp

A read-only, distributed SQL engine for Parquet and Delta Lake data in S3-compatible object storage, built in Rust on [Apache DataFusion Ballista](https://github.com/apache/datafusion-ballista).

octopus-mpp aims at the space Trino occupies — analysts and services querying lake data over SQL — with a smaller footprint: no JVM, no external metastore, a built-in catalog, and a codebase that one person can read end to end.

## Status

**Design phase.** No engine code exists yet. The first version is fully specified under
[`openspec/changes/v1-read-only-engine/`](openspec/changes/v1-read-only-engine/):

- [`proposal.md`](openspec/changes/v1-read-only-engine/proposal.md) — why, what is in and out of scope
- [`design.md`](openspec/changes/v1-read-only-engine/design.md) — architecture and the decisions behind it
- [`specs/`](openspec/changes/v1-read-only-engine/specs/) — behavior contracts for each capability
- [`tasks.md`](openspec/changes/v1-read-only-engine/tasks.md) — the phased implementation plan

## What v1 will do

- **Query** Parquet tables (including Hive-partitioned layouts) and Delta Lake tables stored in MinIO or any S3-compatible storage, distributed across executors.
- **Catalog** tables as `catalog.schema.table` in a built-in persistent catalog managed with SQL DDL or HTTP. No Hive Metastore.
- **Connect** over Arrow Flight SQL (JDBC for DataGrip, ADBC for Python) as the primary protocol, or over a thin HTTP/JSON gateway for browsers, `curl`, and services.
- **Authenticate** every client with username/password, issue per-session tokens, and separate the `admin` and `reader` roles.
- **Operate** with health probes, Prometheus metrics, query history, and the Ballista monitoring UI. A Docker Compose stand with MinIO, one scheduler, and two executors is the reference environment.
- **Verify** correctness with the 22 TPC-H queries over both Parquet and Delta copies of the data.

Not in v1: writes of any kind, Hive Metastore/Glue adapters, multi-scheduler HA, query queues, caching, performance tuning, a custom UI.

## Architecture in one paragraph

Two processes. `octopus-scheduler` embeds the Ballista scheduler and adds the catalog, authentication, the Flight SQL endpoint, and the HTTP gateway; it talks to executors on a cluster-internal port and to clients on two separate ports. `octopus-executor` embeds the Ballista executor plus the same storage configuration and plan codecs, so Parquet and Delta scans run on any node. DataFusion plans and executes, Ballista distributes, and our crates stay thin: catalog, auth, gateway, configuration, and Delta wiring. Anything that must change inside Ballista goes upstream, on a pinned branch until merged.

```
clients (DataGrip / ADBC / curl)
        │ Flight SQL (gRPC)        │ HTTP /v1, /api, /ui
        ▼                          ▼
┌────────────────────── octopus-scheduler ──────────────────────┐
│  auth · sessions · catalog (SQLite) · gateway · Ballista scheduler │
└───────────────────────────┬────────────────────────────────────┘
                            │ cluster-internal gRPC
          ┌─────────────────┴─────────────────┐
          ▼                                   ▼
  octopus-executor                     octopus-executor
  (Ballista executor + storage + codecs)
          │                                   │
          └──────────── S3 / MinIO ───────────┘
                 Parquet · Delta Lake
```

## How work is organized

Development follows [OpenSpec](https://github.com/Fission-AI/OpenSpec): every piece of work is a *change* with a proposal, specs, design, and tasks under `openspec/changes/`, implemented task by task, then archived into `openspec/specs/` as the living specification of the system. The `openspec` CLI validates the artifacts; the `/opsx:*` commands in `.claude/` drive the workflow.

Project rules worth knowing:

- Ballista is a dependency, never a fork. Every change that touches Ballista internals is first checked for upstream demand, agreed with the project owner, reviewed, and only then proposed upstream.
- Architecture clarity is an acceptance criterion: small crates with one job each, documented extension points, an ADR per decision.
- All project artifacts are written in English.

## Building blocks

| Piece | Source |
|---|---|
| SQL planning and execution | [Apache DataFusion](https://datafusion.apache.org/) 55 |
| Distributed scheduling, shuffle, AQE | [Ballista](https://datafusion.apache.org/ballista/) 55 |
| Delta Lake reads | [delta-rs](https://github.com/delta-io/delta-rs) 2.x |
| Client protocol | [Arrow Flight SQL](https://arrow.apache.org/docs/format/FlightSql.html) |
| Object storage | [`object_store`](https://docs.rs/object_store) (S3 / MinIO) |

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
