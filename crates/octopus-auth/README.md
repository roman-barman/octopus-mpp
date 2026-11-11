# octopus-auth

Authentication and authorization for the client-facing endpoints.

**Single responsibility:** load users and roles (`admin`, `reader`) from
configuration with Argon2id password hashes, verify credentials, issue and
expire opaque session tokens in the `TokenStore`, and adapt that to the two
entry points: an implementation of the Ballista Flight SQL `Authenticator`
and an axum middleware accepting Basic or Bearer credentials. Both resolve to
the same session, which is how one token works on both protocols.

Depends on `octopus-config`. Used by `octopus-session`, `octopus-gateway`,
and `octopus-scheduler`.
