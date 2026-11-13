//! The octopus-mpp scheduler process.
//!
//! One job: wire the library crates into Ballista's scheduler. It loads the
//! configuration, installs our catalog, authentication, session builder,
//! plan codecs, and `octopus.*` options into `SchedulerConfig`, and serves
//! the cluster port, the Flight SQL port, and the HTTP gateway port. The
//! wiring arrives with tasks 3.2 and 3.3 (cluster port and `--standalone`)
//! of the `v1-read-only-engine` change and grows as the later phases add
//! the client-facing ports; until then the binary only exits successfully,
//! so that the workspace has something to build, lint, and run.

fn main() {}
