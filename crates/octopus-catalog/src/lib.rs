//! The built-in, persistent table catalog of octopus-mpp.
//!
//! One job: store table and schema definitions durably (SQLite behind the
//! `CatalogStore` trait), present them to DataFusion as a catalog, and build
//! the Parquet and Delta Lake table providers when a query is planned. The
//! implementation arrives with task group 4 of the `v1-read-only-engine`
//! change; until then the crate is an empty workspace member.
