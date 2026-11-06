# Spec Delta

## Purpose

Defines how the scheduler and executor processes are configured, started, probed, stopped, and run together, so that an operator can bring up a working cluster from configuration alone.

## ADDED Requirements

### Requirement: Scheduler process
The system SHALL provide a `octopus-scheduler` executable that plans queries, coordinates executors, and serves all client-facing endpoints (Flight SQL, HTTP gateway, monitoring).

#### Scenario: Scheduler starts with a configuration file
- **WHEN** `octopus-scheduler --config scheduler.toml` is started with a valid configuration
- **THEN** the process listens on the configured cluster-internal port, Flight SQL port, and HTTP port, and logs the resolved configuration with secrets redacted

#### Scenario: Scheduler rejects invalid configuration
- **WHEN** the configuration file is missing a required field or contains an unknown key
- **THEN** the process exits with a non-zero status and an error naming the offending key before binding any port

### Requirement: Executor process
The system SHALL provide a `octopus-executor` executable that registers with a scheduler, executes assigned tasks, and serves shuffle and result data to the cluster.

#### Scenario: Executor registers with the scheduler
- **WHEN** `octopus-executor --config executor.toml` starts and the scheduler is reachable
- **THEN** the executor appears in the scheduler's executor list within one heartbeat interval with its configured vcores and memory pool

#### Scenario: Scheduler unreachable at startup
- **WHEN** the executor starts and the scheduler is not reachable
- **THEN** the executor retries registration for the configured connect timeout and exits with a non-zero status and a clear error if the timeout elapses

### Requirement: Configuration sources
Each process SHALL read a single TOML configuration file and SHALL allow any value to be overridden by an environment variable, with environment variables taking precedence.

#### Scenario: Environment variable overrides a file value
- **WHEN** `scheduler.toml` sets `storage.s3.endpoint = "http://a"` and `OCTOPUS_STORAGE_S3_ENDPOINT=http://b` is set
- **THEN** the effective endpoint is `http://b`

#### Scenario: Secrets provided only through environment
- **WHEN** the S3 secret key is given via environment variable and omitted from the file
- **THEN** the process starts and the secret never appears in logs or in any API response

### Requirement: Health and readiness probes
Each process SHALL expose HTTP `/healthz` (liveness) and `/readyz` (readiness) endpoints without authentication: the scheduler on its HTTP port, the executor on its configured health port.

#### Scenario: Scheduler readiness depends on executors
- **WHEN** the scheduler is running and fewer than the configured minimum number of executors are registered
- **THEN** `/readyz` returns HTTP 503 and `/healthz` returns HTTP 200

#### Scenario: Scheduler becomes ready
- **WHEN** at least the configured minimum number of executors are registered
- **THEN** `/readyz` returns HTTP 200

### Requirement: Graceful shutdown
Each process SHALL stop accepting new work on SIGTERM, finish or cancel in-flight work within a configured grace period, and then exit.

#### Scenario: Executor drains on SIGTERM
- **WHEN** an executor receives SIGTERM while running tasks
- **THEN** it reports itself as stopping to the scheduler, finishes tasks that complete within the grace period, and exits with status 0

#### Scenario: Scheduler cancels queries on SIGTERM
- **WHEN** the scheduler receives SIGTERM with queries running
- **THEN** `/readyz` returns 503 immediately, running queries are cancelled with an error delivered to their clients, and the process exits within the grace period

### Requirement: Executor loss handling
The scheduler SHALL detect an executor that stops sending heartbeats and SHALL remove it from scheduling after the configured timeout.

#### Scenario: Executor killed without notice
- **WHEN** an executor process is killed with SIGKILL
- **THEN** the scheduler marks it dead after the heartbeat timeout, excludes it from new task placement, and handles its running tasks as described in `query-execution`

### Requirement: Reference Docker Compose stand
The repository SHALL provide a Docker Compose definition that starts MinIO, one scheduler, and two executors as separate containers on a shared network, with MinIO pre-provisioned with a bucket for test data.

#### Scenario: Stand comes up from scratch
- **WHEN** `docker compose up` is run in the `deploy/compose` directory on a clean machine with Docker installed
- **THEN** within two minutes the scheduler's `/readyz` returns 200, two executors are listed, and the MinIO bucket exists

#### Scenario: Smoke query on the stand
- **WHEN** a Parquet file is uploaded to the bucket and a client runs `SELECT count(*)` over it through Flight SQL
- **THEN** the correct row count is returned and the job appears as completed in the monitoring API

### Requirement: Standalone mode for development
The system SHALL provide a way to run scheduler and executor inside a single process for local development and unit tests.

#### Scenario: Standalone process answers queries
- **WHEN** `octopus-scheduler --standalone --config dev.toml` is started
- **THEN** it accepts Flight SQL and HTTP queries without any separate executor process

### Requirement: Version compatibility check
The scheduler SHALL refuse to register an executor whose Ballista protocol version differs from its own, and SHALL report both versions in the error.

#### Scenario: Mismatched executor
- **WHEN** an executor built against a different Ballista major version registers
- **THEN** registration is rejected, the scheduler logs both versions, and the executor exits with a non-zero status
