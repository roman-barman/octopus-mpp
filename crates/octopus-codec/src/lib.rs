//! Plan codecs and session options shared by the octopus-mpp processes.
//!
//! One job: define what the scheduler and the executors must agree on over
//! the cluster port, the `OctopusLogicalCodec` and `OctopusPhysicalCodec`
//! that let plan nodes (Delta Lake scans first, Ballista's default codec as
//! the fallback) travel between processes, and the `OctopusOptions` config
//! extension that registers the `octopus.*` session options on both sides.
//! The pass-through codecs and the options arrive with task 2.5 of the
//! `v1-read-only-engine` change, the Delta branch with task 9.2; until then
//! the crate is an empty workspace member.
