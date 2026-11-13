# octopus-codec

What the scheduler and the executors must agree on over the cluster port.

**Single responsibility:** the two Ballista extension points that make a plan
produced on the scheduler executable on any executor: `OctopusLogicalCodec`
and `OctopusPhysicalCodec`, which serialize and deserialize plan nodes (Delta
Lake scans first, Ballista's default codec as the fallback), and the
`OctopusOptions` DataFusion `ConfigExtension` that registers the
`octopus.user`, `octopus.role`, and `octopus.query_timeout` session options,
so that a session configuration shipped to an executor is accepted there. The
codec constructor takes the `[storage.s3]` configuration on the current
assumption (design D8) that a Delta scan decoded on an executor rebuilds its
log store from the table URI and those options; task 9.2 verifies this and
drops the `octopus-storage` dependency if delta-rs does not need it.

Depends on `octopus-config` and `octopus-storage` only, so that the executor
can link it without the catalog, session, or authentication crates. Used by
`octopus-session`, `octopus-scheduler`, and `octopus-executor`, which install
the codecs through Ballista's `override_logical_codec` and
`override_physical_codec` hooks and the options through its config producers.
