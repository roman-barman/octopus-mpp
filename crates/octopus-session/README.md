# octopus-session

Per-session query state and statement interception.

**Single responsibility:** build the DataFusion `SessionState` for each
client session (shared catalog provider, storage registry, Ballista functions
and optimizer rules, `octopus.user`, `octopus.role`, `octopus.query_timeout`)
and inspect every statement before DataFusion sees it: catalog DDL is routed
to `octopus-catalog` with an admin role check, `USE` and `SET SCHEMA` update
the session defaults, write statements are rejected as read-only, and read
statements pass through untouched.

Depends on `octopus-config`, `octopus-storage`, `octopus-catalog`,
`octopus-auth`, and `octopus-codec` (for the `OctopusOptions` type it sets on
the session). Used by `octopus-gateway` and `octopus-scheduler`.

The plan codecs (design D8) are not owned here: they live in `octopus-codec`,
which both binaries install through Ballista's `override_*_codec` hooks, so
that the executor never depends on this crate (it would drag in the catalog
and authentication).
