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

Two processes. `octopus-scheduler` embeds the Ballista scheduler and adds the catalog, authentication, the Flight SQL endpoint, and the HTTP gateway; it talks to executors on a cluster-internal port and to clients on two separate ports. `octopus-executor` embeds the Ballista executor plus the same storage configuration and plan codecs, so Parquet and Delta scans run on any node. DataFusion plans and executes, Ballista distributes, and our crates stay thin: configuration, storage, catalog, auth, sessions, gateway, and the plan codecs that let Delta scans travel to executors. Anything that must change inside Ballista goes upstream, on a pinned branch until merged.

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

## Pull request size

Every pull request is measured in CI (`pr-size` check) and fails when it changes more than 500 lines (additions + deletions) or 20 files, not counting `Cargo.lock` and `openspec/changes/archive/`. The owner has to be able to read every PR in full. The size is measured from the merge-base with the pull request's base branch, and the gate measures again when the base branch is changed (a pull request that conflicts with its new base is measured at its next push). Check before pushing:

```
scripts/ci/pr-size.sh origin/main
```

For a pull request stacked on another branch, pass that branch instead of `main`, for example `scripts/ci/pr-size.sh origin/spec/my-change`.

The only exception is the `size/override` label, which the project owner adds after a written justification why the PR cannot be made smaller. The gate's behavior is specified in [`openspec/specs/pr-size-gate/spec.md`](openspec/specs/pr-size-gate/spec.md).

## Git hooks

The repository ships its git hooks in `scripts/hooks/`. Install them once per clone:

```
scripts/hooks/install.sh
```

They catch the project's rules before CI does: `pre-commit` refuses commits on `main` or on a branch not named `<type>/<topic>` and checks `cargo fmt` on the staged tree; `commit-msg` requires an imperative subject of at most 72 characters and a body line citing the OpenSpec change and tasks (`quality-gates: 2.2`), or, for the files the owner exempted from OpenSpec, a line `No OpenSpec change: <reason>`; `pre-push` refuses pushes to `main`. Everything else (formatting again, clippy, tests, docs, the dependency policy, the PR size limit) is checked by CI on the pull request; see [Quality gates](#quality-gates). The hooks have no skip flag; `--no-verify` is the only bypass and is not used in this project. Their behavior is specified in `openspec/specs/git-hooks/spec.md` and tested by `scripts/hooks/hooks-test.sh`.

## Quality gates

Every pull request runs the `ci` workflow (`.github/workflows/ci.yml`), one job per gate; each job name is a required status check in the `protect-main` ruleset. Each gate is one command that gives the same verdict locally, with the toolchain pinned in `rust-toolchain.toml`:

| Gate | Local command | Fails when |
|---|---|---|
| `fmt` | `cargo fmt --check` | any file differs from `rustfmt` output |
| `clippy` | `cargo clippy --workspace --all-targets -- -D warnings` | any lint warning, including in tests |
| `test` | `cargo test --workspace` | any test fails; tests that need the Compose stand are `#[ignore]` |
| `doc` | `RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps --document-private-items` | any rustdoc warning, such as a broken intra-doc link |
| `deny` | `cargo deny check` | a vulnerable dependency, a license outside the allowlist, two versions of one crate, or a source other than crates.io and the allowed Ballista repositories (`deny.toml`) |
| `deps` | `scripts/ci/crate-deps-test.sh && scripts/ci/crate-deps.sh` | a workspace crate depends on another outside the allowed edges of design D2 of `v1-read-only-engine` (test-only dependencies are not checked) |

`cargo deny` is not part of the toolchain; install once the version `ci.yml` pins in `CARGO_DENY_VERSION`:

```
cargo install cargo-deny --locked --version 0.20.2
```

The lints every crate inherits are in `[workspace.lints]` of the root `Cargo.toml`: `unsafe_code` is forbidden, `clippy::unwrap_used` is an error outside tests, and `missing_docs`, `unreachable_pub`, and `clippy::all` are warnings that CI turns into errors. A local `#[allow(...)]` or `#[expect(...)]` is a decision, so every one states its `reason = "..."`; `clippy::allow_attributes_without_reason` rejects one without it. The gates are specified in `openspec/specs/ci-quality-gates/spec.md`.

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
