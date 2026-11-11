//! Authentication and authorization for octopus-mpp.
//!
//! One job: decide who a client is and what role they hold, on both Flight
//! SQL and HTTP, through one shared token store. The implementation arrives
//! with task group 6 of the `v1-read-only-engine` change; until then the
//! crate is an empty workspace member.
