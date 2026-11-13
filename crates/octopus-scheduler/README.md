# octopus-scheduler

The scheduler process, one of the two octopus-mpp binaries.

**Single responsibility:** wiring. It loads the scheduler configuration,
builds the Ballista `SchedulerConfig` (push-staged scheduling, minimum ready
executors, event log directory, `OctopusOptions` through
`override_config_producer`, the `octopus-codec` codecs through
`override_*_codec`), and starts the Ballista scheduler on the cluster port
together with the Flight SQL endpoint and the HTTP gateway on their own
ports, each behind `octopus-auth`. With `--standalone` it also runs one
Ballista executor in the same process for local development and tests.
No query, catalog, or authentication logic lives here; every behavior comes
from a library crate.

Depends on `octopus-config`, `octopus-storage`, `octopus-catalog`,
`octopus-auth`, `octopus-session`, `octopus-gateway`, and `octopus-codec`.
Nothing depends on it.
