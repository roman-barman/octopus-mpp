# octopus-executor

The executor process, one of the two octopus-mpp binaries.

**Single responsibility:** wiring. It loads the executor configuration,
builds the Ballista `ExecutorProcessConfig` with the storage registry from
`octopus-storage` (runtime producer), the `OctopusOptions` config extension
from `octopus-codec` (config producer),
the `octopus-codec` codecs, and the vcores and memory settings, then starts
the Ballista executor, which registers with the scheduler over the cluster
port and runs the stages it is assigned. No query logic lives here; the
executor is a plain Ballista executor that can read the same storage and
decode the same plans as the scheduler.

Depends on `octopus-config`, `octopus-storage`, and `octopus-codec` only.
It must never link the catalog, session, authentication, or gateway crates:
an executor has no clients and no users, only tasks. Nothing depends on it.
