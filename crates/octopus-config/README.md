# octopus-config

Typed configuration for the two octopus-mpp processes.

**Single responsibility:** read one TOML file per process, apply `OCTOPUS_*`
environment overrides (environment wins), reject unknown keys and missing
required fields with an error that names the key, and keep secrets out of
`Debug` output and logs.

Every other crate in the workspace depends on this one; it depends on nothing
else in the workspace.
