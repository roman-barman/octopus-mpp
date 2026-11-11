//! Per-session query state for octopus-mpp.
//!
//! One job: build the DataFusion session for a client and intercept the
//! statements that DataFusion must not execute itself (catalog DDL,
//! `USE`/`SET SCHEMA`, writes). The implementation arrives with tasks 4.4
//! and 4.5 (session builder, interception) and 6.3 (user and role in the
//! session, admin check for DDL) of the `v1-read-only-engine` change; until
//! then the crate is an empty workspace member.
