# Spec Delta

## Purpose

Defines who may connect to the engine, how they prove their identity, what each role may do, and which network endpoints must stay inside the cluster.

## ADDED Requirements

### Requirement: Users and roles from configuration
The scheduler SHALL load users from its configuration, each with a username, a password hash (Argon2id), and a role of `admin` or `reader`; plain-text passwords SHALL NOT be accepted in configuration.

#### Scenario: Plain-text password rejected
- **WHEN** a user entry contains `password = "secret"` instead of a hash
- **THEN** the scheduler refuses to start and names the user

#### Scenario: Hash generation helper
- **WHEN** an operator runs `octopus-scheduler hash-password`
- **THEN** it reads a password from stdin and prints an Argon2id hash suitable for the configuration

### Requirement: Username and password authentication
Every client entry point (Flight SQL, HTTP) SHALL authenticate clients by username and password and SHALL reject unknown users or wrong passwords with an unauthenticated status without revealing which of the two was wrong.

#### Scenario: Wrong password on Flight SQL
- **WHEN** a Flight SQL handshake presents a valid username with a wrong password
- **THEN** the handshake fails with `UNAUTHENTICATED` and the message "invalid credentials"

#### Scenario: Basic auth on HTTP
- **WHEN** an HTTP request carries valid `Authorization: Basic` credentials
- **THEN** the request is accepted and executed as that user

### Requirement: Bearer tokens and sessions
A successful authentication SHALL yield an opaque bearer token bound to a new session; the token SHALL be accepted on both Flight SQL and HTTP, SHALL expire after a configured idle timeout, and SHALL be revocable by closing the session.

#### Scenario: Token reused across protocols
- **WHEN** a client obtains a token through the Flight SQL handshake and uses it as `Authorization: Bearer` on the HTTP gateway
- **THEN** the HTTP request runs in the same session with the same user and session settings

#### Scenario: Expired token
- **WHEN** a token is unused for longer than the idle timeout and is presented again
- **THEN** the request fails with `UNAUTHENTICATED` and the client must re-authenticate

### Requirement: Session isolation
Session state (current schema, `SET` options, prepared statements, unfetched results) SHALL be private to the session; only catalog contents are shared.

#### Scenario: Two sessions, different settings
- **WHEN** session A sets pipelined mode and session B does not
- **THEN** B's queries run in staged mode

### Requirement: No anonymous access
The engine SHALL NOT provide a shared anonymous session; requests without credentials SHALL be rejected on every client endpoint.

#### Scenario: Handshake without credentials
- **WHEN** a Flight SQL client skips the handshake and calls `GetFlightInfo`
- **THEN** the call fails with `UNAUTHENTICATED`

### Requirement: Role enforcement
Users with role `reader` SHALL be able to run read queries and session statements and browse the catalog; users with role `admin` SHALL additionally be able to run DDL, manage the catalog over HTTP, and see and cancel any user's queries.

#### Scenario: Reader cancels another user's query
- **WHEN** a reader attempts to cancel a statement submitted by a different user
- **THEN** the request fails with a permission-denied error

### Requirement: Client ports and internal ports are separate
Flight SQL and HTTP SHALL be served only on their configured client ports; the scheduler's executor-facing gRPC port and the executors' ports SHALL be documented as cluster-internal, and the scheduler SHALL reject every RPC on its executor-facing port other than executor registration, heartbeat, work polling, task status, and executor-stopped notifications.

#### Scenario: Compose stand exposes only client ports
- **WHEN** the reference Docker Compose stand is started
- **THEN** only the Flight SQL and HTTP ports of the scheduler (and MinIO's ports for test setup) are published to the host

#### Scenario: Native client RPC on the cluster port
- **WHEN** a process on the cluster network calls the Ballista `ExecuteQuery` RPC on the scheduler's executor-facing port
- **THEN** the call fails with `PERMISSION_DENIED`

### Requirement: Statement ownership versus session state
Session state (`SET` options, current schema, prepared statements, result tickets) SHALL be private to the session that created it; submitted statements SHALL be owned by the user and manageable from any of that user's sessions or by an admin.

#### Scenario: Same user, second session
- **WHEN** a user submits a statement over HTTP and later lists statements from a new Flight SQL-issued token
- **THEN** the statement is listed

### Requirement: Result tickets are bound and validated
Result tickets handed to clients SHALL be bound to the issuing session and SHALL be redeemable only by that session; the scheduler SHALL fetch result data only from executors currently registered with it, never from an address supplied in a ticket.

#### Scenario: Ticket replay from another session
- **WHEN** a ticket issued to session A is redeemed with session B's token
- **THEN** the fetch fails with a permission-denied status

#### Scenario: Forged executor address
- **WHEN** a client submits a ticket whose encoded location names an address that is not a registered executor
- **THEN** the scheduler refuses the fetch and does not open a connection to that address

### Requirement: Authentication events are logged
Successful and failed authentications SHALL be logged with username, client address, protocol, and outcome, never with the password or token.

#### Scenario: Failed login logged
- **WHEN** a login fails
- **THEN** a log line at `warn` level records the username and client address
