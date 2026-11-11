# Spec Delta

## Purpose

Defines how the engine reads Delta Lake tables from S3-compatible storage, relying on the Delta transaction log for schema, file list, and partition information.

## ADDED Requirements

### Requirement: Delta table registration
The system SHALL accept a Delta table by its root location (`STORED AS DELTA LOCATION '<url>'`) and SHALL take the schema, partition columns, and file list from the `_delta_log` directory, with no explicit column list or `PARTITIONED BY` required.

#### Scenario: Register and query
- **WHEN** a Delta table written by an external writer is registered by location
- **THEN** `DESCRIBE` shows the schema from the log and `SELECT count(*)` returns the row count of the current table version

#### Scenario: Location is not a Delta table
- **WHEN** the location has no `_delta_log` directory
- **THEN** registration fails with an error stating that no Delta log was found

### Requirement: Snapshot isolation per query
Each query SHALL read a single consistent table version resolved at planning time, so that concurrent commits by external writers do not produce mixed results within one query.

#### Scenario: Commit during query
- **WHEN** a commit lands while a long query over the table is running
- **THEN** the query's result reflects only the version resolved at its start

### Requirement: Latest version by default, pinned version by registration
The system SHALL read the latest committed version at planning time, and SHALL allow a table to be registered at a fixed version with `OPTIONS (version = '<n>')`, in which case every query over that table reads that version.

#### Scenario: Pinned version
- **WHEN** an admin registers `events_v3 STORED AS DELTA LOCATION '...' OPTIONS (version = '3')` and a client queries it after later commits
- **THEN** rows reflect version 3 of the table

#### Scenario: Per-query time travel not supported
- **WHEN** a client runs `SELECT * FROM events FOR VERSION AS OF 3`
- **THEN** the statement fails with a parse error, and the catalog documentation explains that time travel is done by registering a pinned version

### Requirement: Partition and file pruning from the log
The system SHALL use partition values and per-file column statistics recorded in the Delta log to skip files excluded by query predicates, without listing the storage prefix.

#### Scenario: Filter on partition column
- **WHEN** a Delta table partitioned by `region` is queried with `WHERE region = 'eu'`
- **THEN** only files whose log entry has `region = eu` are read

### Requirement: Deletion vectors and column mapping
The system SHALL correctly read tables that use deletion vectors and column mapping (name or id mode), returning only live rows and the logical column names.

#### Scenario: Deletion vectors
- **WHEN** rows were deleted with deletion vectors enabled
- **THEN** a `SELECT` returns only non-deleted rows

### Requirement: Unsupported features fail clearly
When a Delta table requires a reader feature the engine does not support, registration or query SHALL fail with an error naming the feature.

#### Scenario: Unknown reader feature
- **WHEN** the table protocol lists a reader feature the engine does not implement
- **THEN** the error message contains that feature name

### Requirement: Distributed Delta scans
Delta table scans SHALL be distributed across executors like Parquet scans, with the file list resolved once on the scheduler and shipped to executors with the plan.

#### Scenario: Scan tasks on multiple executors
- **WHEN** a Delta table with many files is queried on a two-executor stand
- **THEN** both executors run scan tasks for it

### Requirement: Correctness on the reference workload
Queries over the TPC-H tables stored as Delta SHALL return the same results as over the same data in plain Parquet.

#### Scenario: Parquet and Delta agree
- **WHEN** the harness runs the TPC-H queries over both the Parquet and Delta copies of the tables
- **THEN** results are identical
