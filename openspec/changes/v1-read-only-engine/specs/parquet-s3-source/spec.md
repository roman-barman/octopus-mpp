# Spec Delta

## Purpose

Defines how the engine reads Parquet tables stored in S3-compatible object storage such as MinIO, including partitioned layouts and the pruning behavior users can rely on.

## ADDED Requirements

### Requirement: S3-compatible storage configuration
The system SHALL read Parquet data from any S3-compatible endpoint configured per process with endpoint URL, region, access key, secret key, optional session token, path-style addressing flag, and an allow-HTTP flag; the same configuration SHALL apply on scheduler and executors.

#### Scenario: MinIO over HTTP with path-style URLs
- **WHEN** storage is configured with `endpoint = "http://minio:9000"`, `path_style = true`, `allow_http = true`
- **THEN** `s3://bucket/path/` locations resolve and files are read successfully

#### Scenario: Wrong credentials
- **WHEN** the configured secret key is wrong
- **THEN** table registration and queries fail with an access-denied error that names the bucket but not the credentials

### Requirement: Credentials never travel through SQL
The system SHALL NOT accept storage credentials through SQL `SET` statements or table options; credentials come only from process configuration.

#### Scenario: Credential via SET rejected
- **WHEN** a client runs `SET s3.secret_access_key = '...'`
- **THEN** the statement fails with an error stating the option is not settable

### Requirement: Directory and file locations
A table location SHALL be either a single Parquet object or a prefix under which all objects with the `.parquet` extension are read recursively.

#### Scenario: Prefix with nested directories
- **WHEN** a table's location is `s3://data/t/` containing files in nested sub-prefixes
- **THEN** all `.parquet` objects under the prefix are read and non-Parquet objects are ignored

### Requirement: Hive-style partitioning
The system SHALL recognize `key=value` directory segments under the table location as partition columns when declared with `PARTITIONED BY`, SHALL expose them as table columns, and SHALL skip partitions excluded by query predicates.

#### Scenario: Partition pruning
- **WHEN** a table partitioned by `dt` is queried with `WHERE dt = '2026-01-01'`
- **THEN** only objects under `dt=2026-01-01/` are listed and read, verifiable in `EXPLAIN ANALYZE` file counts

#### Scenario: Partition column type
- **WHEN** `PARTITIONED BY (dt DATE)` is declared
- **THEN** the `dt` column is typed `DATE` and comparisons use date semantics

### Requirement: Row group and page pruning
The system SHALL use Parquet statistics to skip row groups that cannot match query predicates, and SHALL read only the columns referenced by the query.

#### Scenario: Selective filter
- **WHEN** a query filters on a column with min/max statistics covering disjoint ranges per row group
- **THEN** `EXPLAIN ANALYZE` shows fewer row groups read than the table contains

### Requirement: Schema inference across files
When no explicit schema is given the system SHALL infer the table schema from the Parquet files, merging compatible schemas and failing with a clear error when files have incompatible types for the same column.

#### Scenario: Incompatible files
- **WHEN** two files define column `x` as `INT64` and `VARCHAR`
- **THEN** registration fails with an error naming the column and both files

### Requirement: Supported Parquet types
The system SHALL read all Parquet physical and logical types supported by the embedded Arrow Parquet reader, including nested structs, lists, maps, decimals, and timestamps with and without time zone.

#### Scenario: Nested columns
- **WHEN** a table has a `STRUCT` column with a nested `LIST`
- **THEN** `SELECT col.field[1] FROM t` returns the correct values

### Requirement: Scan parallelism
The system SHALL split a table scan into tasks across files and, for large files, across row groups, so that executors read concurrently.

#### Scenario: Many small files
- **WHEN** a table has hundreds of small Parquet files
- **THEN** scan tasks are distributed over all executors and no single task reads every file
