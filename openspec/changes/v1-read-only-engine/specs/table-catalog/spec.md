# Spec Delta

## Purpose

Defines the built-in, persistent catalog through which users register and discover tables, so that queries can name tables as `catalog.schema.table` without any external metastore.

## ADDED Requirements

### Requirement: Three-level naming
The system SHALL organize tables as `catalog.schema.table`, SHALL provide a default catalog named `octopus` and a default schema named `default`, and SHALL resolve unqualified names against the session's current catalog and schema.

#### Scenario: Unqualified name resolves to defaults
- **WHEN** a table was registered as `octopus.default.orders` and a client runs `SELECT * FROM orders`
- **THEN** the query reads `octopus.default.orders`

#### Scenario: Session changes current schema
- **WHEN** a client runs `SET SCHEMA sales` (or `USE octopus.sales`) and then `SELECT * FROM orders`
- **THEN** the query reads `octopus.sales.orders`

### Requirement: Schema management
The system SHALL support `CREATE SCHEMA [IF NOT EXISTS] <name>` and `DROP SCHEMA [IF EXISTS] <name>`, where dropping a non-empty schema fails unless `CASCADE` is given.

#### Scenario: Drop non-empty schema without CASCADE
- **WHEN** a client runs `DROP SCHEMA sales` and `sales` contains tables
- **THEN** the statement fails with an error listing that the schema is not empty

### Requirement: Register external table
The system SHALL support `CREATE EXTERNAL TABLE [IF NOT EXISTS] <name> STORED AS (PARQUET | DELTA) [PARTITIONED BY (...)] LOCATION '<url>' [OPTIONS (...)]`, where the schema is inferred from the data at the location when not given explicitly.

#### Scenario: Register Parquet table with inferred schema
- **WHEN** a client runs `CREATE EXTERNAL TABLE orders STORED AS PARQUET LOCATION 's3://data/tpch/orders/'`
- **THEN** the table is created with the schema read from the Parquet files and is immediately queryable from any session

#### Scenario: Register Delta table
- **WHEN** a client runs `CREATE EXTERNAL TABLE events STORED AS DELTA LOCATION 's3://data/events/'`
- **THEN** the table is created and its schema is taken from the Delta transaction log

#### Scenario: Location unreadable
- **WHEN** the location does not exist or the storage credentials are rejected
- **THEN** the statement fails with an error that includes the storage error, and no table is created

#### Scenario: Explicit column list
- **WHEN** the statement includes an explicit column list
- **THEN** the table uses that schema and the data files are read with it, casting where the file schema is compatible

### Requirement: Drop table
The system SHALL support `DROP TABLE [IF EXISTS] <name>`, removing only the catalog entry and never the underlying data.

#### Scenario: Drop leaves data intact
- **WHEN** a client drops a registered table
- **THEN** the table disappears from the catalog and the objects at its location are unchanged

### Requirement: Persistence
Catalog contents SHALL survive scheduler restarts and SHALL be identical for all sessions.

#### Scenario: Restart preserves tables
- **WHEN** tables are registered, the scheduler is restarted, and a new client connects
- **THEN** `SHOW TABLES` lists the same tables and they are queryable

#### Scenario: Visible across sessions
- **WHEN** one client registers a table
- **THEN** a second, already connected client can query it without reconnecting

### Requirement: Introspection
The system SHALL expose the catalog through `information_schema` (`tables`, `columns`, `schemata`), through `SHOW CATALOGS`, `SHOW SCHEMAS`, `SHOW TABLES`, `SHOW COLUMNS FROM`, and `DESCRIBE <table>`, and through the Flight SQL metadata commands.

#### Scenario: Client tool browses the catalog
- **WHEN** a JDBC client requests the schema and table list
- **THEN** it receives every registered schema and table with column names and types

### Requirement: Schema refresh for Delta tables
For Delta tables the system SHALL read the current schema and file list from the transaction log at query planning time, so schema evolution and new commits are visible without re-registration.

#### Scenario: New commit appears
- **WHEN** new data is committed to a registered Delta table by an external writer
- **THEN** the next query over that table includes the new rows

### Requirement: Schema refresh for Parquet tables
For Parquet tables the system SHALL persist the inferred schema at registration and SHALL provide `ALTER TABLE <name> REFRESH SCHEMA` to re-infer it, while new files under the location SHALL be picked up at every query without re-registration.

#### Scenario: New file appears
- **WHEN** a new Parquet file with the same schema is added under a registered table's location
- **THEN** the next query over that table includes its rows

#### Scenario: Schema refresh
- **WHEN** files with an added column appear and a client runs `ALTER TABLE t REFRESH SCHEMA`
- **THEN** subsequent `DESCRIBE t` shows the new column

### Requirement: Catalog operations require admin role
DDL statements (`CREATE`, `DROP`, `ALTER`) SHALL be accepted only from sessions whose user has the `admin` role; other users SHALL receive a permission error.

#### Scenario: Reader attempts DDL
- **WHEN** a user with the `reader` role runs `CREATE EXTERNAL TABLE ...`
- **THEN** the statement fails with a permission-denied error and the catalog is unchanged

### Requirement: Catalog state is also manageable over HTTP
Every catalog operation available through SQL DDL SHALL also be available through the HTTP gateway as defined in `http-gateway`, producing identical catalog state.

#### Scenario: Table registered over HTTP is visible in SQL
- **WHEN** a table is registered through the HTTP catalog endpoint
- **THEN** `SHOW TABLES` in a Flight SQL session lists it
