# Spec Delta

## Purpose

Defines the SQL surface the engine accepts, how a query is executed across executors, how memory and failures are handled, and what correctness the engine guarantees.

## ADDED Requirements

### Requirement: Read-only SQL surface
The system SHALL accept and execute read-only SQL: `SELECT` with joins, aggregations, window functions, CTEs, subqueries, set operations, `ORDER BY`, `LIMIT`/`OFFSET`, and the scalar, aggregate, and window functions of the embedded DataFusion version; plus catalog DDL and session statements defined in `table-catalog`.

#### Scenario: Complex analytical query
- **WHEN** a client submits a query with a four-table join, a correlated subquery, a window function, and a `GROUP BY ... HAVING`
- **THEN** the query is planned, distributed, and returns the correct result

#### Scenario: Write statement rejected
- **WHEN** a client submits `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `COPY`, or `CREATE TABLE ... AS SELECT`
- **THEN** the statement is rejected before execution with an error stating that the engine is read-only

### Requirement: Distributed execution across executors
The system SHALL split each query into stages and execute their tasks on registered executors, using all registered executors' vcores subject to configured limits.

#### Scenario: Scan spread over executors
- **WHEN** a table with many Parquet files is scanned on a stand with two executors
- **THEN** both executors execute scan tasks for the query, visible in the per-stage task detail of the monitoring API

### Requirement: Execution modes
The system SHALL support a staged execution mode (default) that materializes stage output and survives task failures, and a pipelined execution mode selectable per session that streams between stages.

#### Scenario: Session selects pipelined mode
- **WHEN** a client runs `SET ballista.execution.mode = 'pipelined'` and then a query
- **THEN** the query runs in pipelined mode and its results begin streaming before all stages have finished

#### Scenario: Default is staged
- **WHEN** a session has not set an execution mode
- **THEN** queries run in staged mode

### Requirement: Task retry in staged mode
In staged mode the system SHALL retry a failed task on another executor up to a configured number of attempts, and SHALL recompute lost stage outputs when an executor is lost.

#### Scenario: Executor dies mid-query
- **WHEN** an executor is killed while a staged query is running
- **THEN** the query still completes with the correct result using the remaining executor, and the monitoring API shows the retried tasks

#### Scenario: Retry budget exhausted
- **WHEN** a task fails more than the configured maximum number of attempts
- **THEN** the query fails with an error that includes the last task error

### Requirement: Pipelined mode failure semantics
In pipelined mode the system SHALL fail the whole query when any of its tasks fails or an executor running one of its tasks is lost, and SHALL report the cause to the client.

#### Scenario: Executor lost during pipelined query
- **WHEN** an executor is killed while a pipelined query runs
- **THEN** the client receives an error naming the lost executor, and no partial result is reported as complete

### Requirement: Memory limits and spilling
Each executor SHALL bound the memory used by query tasks to a configured pool, SHALL spill sort and aggregation state to local disk when the pool is exhausted, and SHALL fail a query with a resource error rather than terminate the process when spilling is not possible.

#### Scenario: Large sort within limits
- **WHEN** a query sorts more data than fits in the executor memory pool
- **THEN** the query completes by spilling to the configured work directory

#### Scenario: Memory exhausted without spill
- **WHEN** a hash join build side exceeds the available pool
- **THEN** the query fails with an error identifying the operator and the memory limit, and the executor keeps running other queries

### Requirement: Query cancellation
The system SHALL stop all tasks of a query on the executors within a bounded time after the query is cancelled by a client or by the scheduler.

#### Scenario: Client cancels a long query
- **WHEN** a client cancels a running query
- **THEN** every executor stops its tasks for that query within five seconds and the query is recorded as cancelled

### Requirement: Query time limit
The system SHALL support a per-session maximum query duration; a query exceeding it SHALL be cancelled with a timeout error.

#### Scenario: Query exceeds limit
- **WHEN** `SET octopus.query_timeout = '30s'` is set and a query runs longer than 30 seconds
- **THEN** the query is cancelled and the client receives a timeout error

### Requirement: Correctness on the reference workload
The system SHALL return results identical to a single-node DataFusion reference for all 22 TPC-H queries at scale factor 1 over Parquet tables, and for the same queries over tables stored in Delta Lake format.

#### Scenario: TPC-H suite passes on Parquet
- **WHEN** the integration harness runs the 22 TPC-H queries against the Parquet dataset on the Compose stand
- **THEN** every result matches the reference row-for-row within numeric tolerance

#### Scenario: TPC-H suite passes on Delta
- **WHEN** the harness runs the same queries with the tables registered as Delta Lake tables
- **THEN** every result matches the reference

### Requirement: Concurrent queries
The system SHALL execute queries from multiple sessions concurrently, sharing executor vcores, without one session's failure affecting another's query.

#### Scenario: Two sessions, one failing
- **WHEN** two clients run queries at the same time and one query fails with a resource error
- **THEN** the other query completes with the correct result

### Requirement: EXPLAIN
The system SHALL support `EXPLAIN` returning the logical and distributed physical plan, and `EXPLAIN ANALYZE` returning the plan with per-stage execution metrics.

#### Scenario: EXPLAIN shows stage boundaries
- **WHEN** a client runs `EXPLAIN SELECT ... JOIN ...`
- **THEN** the output shows the stages and the exchanges between them without executing the query
