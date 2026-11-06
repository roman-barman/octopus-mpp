# Spec Delta

## Purpose

Defines the Arrow Flight SQL endpoint, the primary protocol through which JDBC, ADBC, and other Arrow-native clients authenticate, run queries, browse metadata, and stream results.

## ADDED Requirements

### Requirement: Flight SQL endpoint on a dedicated port
The scheduler SHALL serve Arrow Flight SQL over gRPC on a port configured separately from the cluster-internal scheduler port, and SHALL serve no cluster-internal RPC on that port.

#### Scenario: Internal RPC not reachable on client port
- **WHEN** a client calls the executor registration RPC on the Flight SQL port
- **THEN** the call fails with an unimplemented or unauthenticated status

### Requirement: Standard clients connect unmodified
The endpoint SHALL be usable by the Arrow Flight SQL JDBC driver (as used by DataGrip) and by `adbc-driver-flightsql` without custom code.

#### Scenario: DataGrip connects
- **WHEN** DataGrip is configured with the Flight SQL JDBC driver, the scheduler address, username, and password
- **THEN** the connection succeeds, the schema browser lists catalogs, schemas, tables, and columns, and queries run from the console

#### Scenario: Python ADBC connects
- **WHEN** a Python program connects with `adbc_driver_flightsql.dbapi.connect(uri, db_kwargs={username, password})`
- **THEN** `cursor.execute(...)` and `fetch_arrow_table()` return Arrow results

### Requirement: Statement execution
The endpoint SHALL execute SQL statements submitted through `CommandStatementQuery`, returning one or more Flight endpoints whose tickets stream the result as Arrow record batches with the exact result schema.

#### Scenario: Result schema matches data
- **WHEN** a query returns nullable and non-nullable columns
- **THEN** the schema advertised in `FlightInfo` matches the schema of every streamed batch

### Requirement: Long-running query polling
The endpoint SHALL implement `PollFlightInfo` so that a client can submit a query, receive a handle immediately, and poll for completion without a long-blocking call.

#### Scenario: Poll until done
- **WHEN** a client submits a query that takes a minute and polls every second
- **THEN** each poll returns progress until the final poll returns the endpoints, and no single call blocks longer than a configured bound

### Requirement: Cancellation
The endpoint SHALL implement `CancelFlightInfo` / `CancelQuery` so a client can cancel a submitted or running query, and SHALL cancel a running query whose client disconnects before consuming its results.

#### Scenario: Explicit cancel
- **WHEN** a client cancels a query obtained through polling
- **THEN** the query is cancelled on the cluster within five seconds and subsequent fetches of its tickets fail with a cancelled status

#### Scenario: Client disconnects
- **WHEN** a client connection drops while its query is running and no ticket has been redeemed
- **THEN** the query is cancelled within the configured session idle timeout

### Requirement: Prepared statements with parameters
The endpoint SHALL support `CreatePreparedStatement`, binding of parameter values through `DoPut`, execution, and `ClosePreparedStatement`, with parameter types reported in the prepared statement's parameter schema.

#### Scenario: Bound parameter query
- **WHEN** a client prepares `SELECT * FROM orders WHERE o_orderkey = ?`, binds `42`, and executes
- **THEN** the result contains only the matching row

#### Scenario: Wrong parameter count
- **WHEN** a client binds two values for a statement with one parameter
- **THEN** execution fails with an invalid-argument status describing the mismatch

### Requirement: Catalog metadata commands
The endpoint SHALL implement `GetCatalogs`, `GetDbSchemas`, `GetTables` (with and without schema), `GetTableTypes`, `GetSqlInfo`, and `GetXdbcTypeInfo`, answering from the shared catalog.

#### Scenario: GetTables with filter
- **WHEN** a client calls `GetTables` with schema pattern `sales` and table pattern `ord%`
- **THEN** only matching tables are returned, with their Arrow schemas when requested

### Requirement: Session statements
The endpoint SHALL execute `SET`, `USE`, `SET SCHEMA`, and `SHOW` statements within the client's session and return their results as Arrow batches.

#### Scenario: SET persists in session
- **WHEN** a client runs `SET ballista.execution.mode = 'pipelined'` and then a query in the same connection
- **THEN** the query runs in pipelined mode

### Requirement: Results streamed from the cluster
Result data SHALL be streamed to the client from a client-reachable endpoint; clients SHALL never need network access to executors.

#### Scenario: Executors on a private network
- **WHEN** the client can reach only the scheduler's client ports and not the executors
- **THEN** results are still fully retrievable

### Requirement: Error reporting
Query failures SHALL be returned as gRPC statuses whose message includes the user-facing error text (planning error, missing table, execution error) without internal stack traces.

#### Scenario: Unknown table
- **WHEN** a client queries a table that does not exist
- **THEN** the status is `NOT_FOUND`/`INVALID_ARGUMENT` with a message naming the table
