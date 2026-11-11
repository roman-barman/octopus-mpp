//! Configuration types for the octopus-mpp processes.
//!
//! This crate has one job: turn a TOML file plus `OCTOPUS_*` environment
//! overrides into validated, typed configuration structs for
//! `octopus-scheduler` and `octopus-executor`, with secrets redacted in
//! `Debug` output. The types arrive with task 2.1 of the
//! `v1-read-only-engine` change; until then the crate is an empty member
//! that gives the workspace something to build, format, lint, and test.
