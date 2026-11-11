# octopus-catalog

The built-in, persistent table catalog.

**Single responsibility:** own everything about `catalog.schema.table`
definitions. It defines the `CatalogStore` trait and its SQLite
implementation, exposes the stored tables to DataFusion through
`CatalogProvider`/`SchemaProvider`, builds `TableProvider`s for Parquet
(`ListingTable`) and Delta Lake (`DeltaTableProvider`) at planning time, and
executes catalog DDL (`CREATE EXTERNAL TABLE`, `DROP TABLE`, `CREATE/DROP
SCHEMA`, `ALTER TABLE ... REFRESH SCHEMA`) including Parquet schema inference.

Depends on `octopus-config` and `octopus-storage`. Used by `octopus-session`,
`octopus-gateway`, and `octopus-scheduler`.
