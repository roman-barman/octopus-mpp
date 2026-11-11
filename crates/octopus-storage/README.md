# octopus-storage

Object storage access for every octopus-mpp process.

**Single responsibility:** turn the `[storage.s3]` section of the process
configuration (endpoint, region, credentials, path-style and allow-HTTP flags)
into the two forms the engine needs: a DataFusion `ObjectStoreRegistry` that
resolves `s3://` (MinIO or any S3-compatible endpoint) and `file://`
locations, and the delta-rs storage options map, so that Parquet scans, schema
inference, and Delta log reads all use the same endpoint and credentials. The
registry is installed in the scheduler runtime and in the executor runtime
alike. Storage credentials never come from SQL.

Depends on `octopus-config`. Used by `octopus-catalog`, `octopus-codec`,
`octopus-session`, `octopus-scheduler`, and `octopus-executor`.
