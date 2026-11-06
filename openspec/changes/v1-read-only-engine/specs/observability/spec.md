# Spec Delta

## Purpose

Defines what operators can see about the cluster and its queries: live and historical query state, plans, metrics, and logs.

## ADDED Requirements

### Requirement: Live query monitoring API
The scheduler SHALL expose a monitoring REST API, available to admins, listing executors, running and recently finished queries, and for each query its SQL text, user, client protocol, state, timings, stages, tasks, and plan in DOT format.

#### Scenario: Running query visible
- **WHEN** a query is running
- **THEN** `GET /api/jobs` lists it with state `RUNNING` and `GET /api/job/{id}/stages` shows per-stage task progress

#### Scenario: Query attributed to user
- **WHEN** a query submitted by user `alice` is listed
- **THEN** the entry includes `"user": "alice"`

### Requirement: Web monitoring UI
The system SHALL serve a browser UI from the scheduler's HTTP port that shows executors, queries, stages, and plans using the monitoring API, authenticated with the same admin credentials.

#### Scenario: Operator opens the UI
- **WHEN** an admin opens `/ui` on the scheduler's HTTP address and authenticates
- **THEN** the UI shows the executor list and the query list

### Requirement: Query history
Completed, failed, and cancelled queries SHALL be recorded durably with their summary, plan, and per-stage metrics, and SHALL remain browsable after a scheduler restart for a configured retention period.

#### Scenario: History survives restart
- **WHEN** queries complete, the scheduler restarts, and an operator lists history
- **THEN** the completed queries are listed with their timings and plans

### Requirement: Prometheus metrics
The scheduler SHALL expose Prometheus metrics on its HTTP port at `/metrics`, including queries submitted/completed/failed/cancelled, query latency histogram, active executors, and per-executor (labelled by executor id) tasks running, task time, and shuffle bytes.

#### Scenario: Metrics scrape
- **WHEN** Prometheus scrapes `/metrics` on the scheduler
- **THEN** the response contains the listed metric families in text exposition format, with executor-level series carrying an `executor` label

### Requirement: Structured logging
Each process SHALL emit structured logs (JSON or key-value, configurable) with level, timestamp, component, and, where applicable, query id and user; log level SHALL be configurable per module at startup.

#### Scenario: Query id in logs
- **WHEN** a query fails on an executor
- **THEN** the executor's error log line includes the query id matching the one shown to the client

### Requirement: Per-query execution metrics for clients
`EXPLAIN ANALYZE` SHALL return per-stage and per-operator metrics (rows, bytes, time, spill) and the final page of an HTTP statement SHALL include elapsed time, rows, bytes scanned, and stage count.

#### Scenario: Statistics on final page
- **WHEN** a client fetches the last page of an HTTP statement
- **THEN** the body includes `stats` with elapsed milliseconds, rows, bytes scanned, and number of stages

### Requirement: Executor and scheduler identity
Every executor and scheduler SHALL have a stable identifier configurable in its configuration and visible in the monitoring API, logs, and metrics labels.

#### Scenario: Named executor
- **WHEN** an executor is configured with `id = "exec-1"`
- **THEN** the monitoring API lists it as `exec-1` and the scheduler's executor-level metrics for it carry the label `executor="exec-1"`
