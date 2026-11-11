//! Object storage access for octopus-mpp.
//!
//! One job: turn the `[storage.s3]` configuration into the two forms the
//! engine needs, a DataFusion `ObjectStoreRegistry` that resolves `s3://`
//! (MinIO or any S3-compatible endpoint) and `file://` locations, and the
//! delta-rs storage options map, so that every reader uses the same endpoint
//! and credentials on scheduler and executors alike. The implementation
//! arrives with task 2.2 of the `v1-read-only-engine` change; until then the
//! crate is an empty workspace member.
