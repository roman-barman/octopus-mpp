//! The octopus-mpp executor process.
//!
//! One job: wire the shared storage registry, the plan codecs, and the
//! `octopus.*` options into Ballista's `ExecutorProcessConfig` and start the
//! Ballista executor. The wiring arrives with task 3.1 of the
//! `v1-read-only-engine` change; until then the binary only exits
//! successfully, so that the workspace has something to build, lint, and
//! run.

fn main() {}
