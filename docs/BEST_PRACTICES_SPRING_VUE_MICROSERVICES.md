# Engineering Best Practices

## Spring Boot + Vue + Microservices + Keycloak + PostgreSQL

**Document status:** Living Engineering Standard  
**Applies to:** Backend, Frontend, APIs, Microservices, Authentication, Database, Infrastructure and CI/CD  
**Primary stack:** Java / Spring Boot, Vue, REST APIs, Keycloak, PostgreSQL

---

## 1. Purpose

This document defines the engineering standards for the project.

The objectives are:

- Keep the system maintainable as it grows.
- Minimize coupling between microservices.
- Make security a default rather than an afterthought.
- Keep business logic testable and independent from infrastructure.
- Ensure database changes are controlled and reproducible.
- Maintain consistent API contracts.
- Make failures observable and diagnosable.
- Prevent technical shortcuts from becoming permanent architecture.

These rules should be treated as the project's default engineering policy.

When a rule must be broken, the reason should be documented in the pull request or architecture decision record.

---

# 2. Core Engineering Principles

## 2.1 Prefer simplicity

Do not introduce technology, abstraction, service or framework complexity unless it solves a real problem.

Prefer:

1. Simple solution.
2. Well-tested solution.
3. Observable solution.
4. Scalable solution when scalability is actually required.

Do not optimize for hypothetical requirements.

---

## 2.2 Explicit over implicit

Important behavior should be visible in code and configuration.

Avoid:

- Hidden global state.
- Magic constants.
- Implicit database behavior.
- Undocumented environment variables.
- Undocumented API behavior.
- Framework features that obscure business rules.

---

## 2.3 Business logic must not depend on infrastructure

Business rules should not require:

- PostgreSQL.
- Keycloak.
- HTTP.
- Redis.
- Kafka/RabbitMQ.
- Spring-specific infrastructure.

Use interfaces/ports where infrastructure dependencies are required.

Recommended conceptual structure:

```text
domain/
application/
infrastructure/
interfaces/
```

The exact package structure can vary, but dependency direction must remain controlled.

---

## 2.4 Fail explicitly

Never silently ignore an error.

Bad:

```java
try {
    doSomething();
} catch (Exception ignored) {
}
```

Better:

```java
try {
    doSomething();
} catch (ExternalServiceException ex) {
    log.error("Failed to process external service request", ex);
    throw new ApplicationException("Unable to complete operation", ex);
}
```

Errors must either:

- Be handled.
- Be translated into an appropriate domain/application error.
- Be propagated with sufficient context.

---

# 3. Microservices Architecture

## 3.1 Service boundaries

A microservice should represent a meaningful business capability.

Do not create services simply because a class or database table exists.

Good examples:

```text
identity-service
player-service
economy-service
fleet-service
research-service
notification-service
```

Bad examples:

```text
user-name-service
player-name-service
database-service
utils-service
```

The correct boundaries depend on the domain.

---

## 3.2 Each service owns its data

A microservice must own its persistence model.

Preferred:

```text
Service A
   |
   +--> PostgreSQL schema/database A

Service B
   |
   +--> PostgreSQL schema/database B
```

Avoid:

```text
Service A ----\
Service B -----+--> same tables
Service C ----/
```

Services must not directly read or modify another service's tables.

If information belongs to another service, use:

- REST API.
- Asynchronous events.
- Read models.
- Replicated data where justified.

---

## 3.3 Database-per-service principle

The architectural goal should be:

> A service owns its data and controls how that data changes.

Using one PostgreSQL cluster is acceptable.

Using one PostgreSQL database with separate schemas can also be acceptable when operational requirements justify it.

The important rule is logical ownership and isolation, not necessarily running a separate PostgreSQL server for every service.

---

## 3.4 Synchronous communication

Use REST/HTTP when:

- The caller needs an immediate response.
- The operation is request/response oriented.
- Strong immediate consistency is required.

Avoid long chains such as:

```text
A -> B -> C -> D -> E
```

These create latency and failure propagation.

Prefer asynchronous events when immediate responses are not required.

---

## 3.5 Asynchronous communication

Events should represent facts that happened.

Examples:

```text
PlayerCreated
ResearchCompleted
FleetDispatched
PaymentCompleted
OrderCancelled
```

Avoid events that represent commands disguised as events:

```text
PleaseCreatePlayer
DoResearchNow
UpdateSomething
```

Commands and events have different semantics.

---

## 3.6 Event design

Events should contain:

- Event ID.
- Event type.
- Event version.
- Timestamp.
- Producer/service.
- Correlation ID.
- Relevant payload.

Example:

```json
{
  "eventId": "uuid",
  "eventType": "ResearchCompleted",
  "version": 1,
  "occurredAt": "2026-08-25T22:00:00Z",
  "producer": "research-service",
  "correlationId": "uuid",
  "data": {
    "playerId": "uuid",
    "researchId": "laser"
  }
}
```

Events should be versioned.

Consumers should tolerate compatible additions to event payloads.

---

## 3.7 Distributed transactions

Do not use distributed database transactions across microservices unless there is an exceptional and documented reason.

Prefer:

- Saga patterns.
- Outbox pattern.
- Idempotent consumers.
- Compensating actions.
- Eventual consistency.

---

# 4. Spring Boot Standards

## 4.1 Layering

A recommended structure:

```text
com.example.service
├── domain
│   ├── model
│   ├── service
│   └── exception
├── application
│   ├── usecase
│   ├── command
│   └── query
├── infrastructure
│   ├── persistence
│   ├── messaging
│   └── security
└── interfaces
    └── rest
```

Do not allow controllers to contain business logic.

---

## 4.2 Controllers

Controllers should be thin.

They should:

1. Validate input.
2. Authenticate/authorize.
3. Map request DTOs.
4. Call an application use case.
5. Map the response.

Avoid:

```java
@PostMapping
public ResponseEntity<?> create(...) {
    // 100 lines of business logic
}
```

Prefer:

```java
@PostMapping
public ResponseEntity<PlayerResponse> create(
        @Valid @RequestBody CreatePlayerRequest request) {

    Player player = createPlayerUseCase.execute(request);

    return ResponseEntity
            .status(HttpStatus.CREATED)
            .body(playerMapper.toResponse(player));
}
```

---

## 4.3 DTOs

Do not expose JPA entities directly through REST APIs.

Use DTOs:

```text
Request DTO
Response DTO
Domain Model
Persistence Entity
```

This prevents API contracts from becoming coupled to the database model.

---

## 4.4 Validation

Validate input at the API boundary.

Example:

```java
public record CreatePlayerRequest(
    @NotBlank
    @Size(max = 50)
    String name
) {}
```

Validation must also exist at the domain level for business invariants.

Never rely exclusively on frontend validation.

---

## 4.5 Exception handling

Use centralized exception handling.

Recommended:

```java
@RestControllerAdvice
public class GlobalExceptionHandler {
}
```

Return a consistent error format.

Example:

```json
{
  "timestamp": "2026-08-25T22:00:00Z",
  "status": 400,
  "code": "INVALID_PLAYER_NAME",
  "message": "Player name is invalid",
  "path": "/api/players",
  "correlationId": "uuid"
}
```

Do not expose:

- Stack traces.
- SQL errors.
- Internal class names.
- Credentials.
- Infrastructure details.

---

## 4.6 Configuration

Never hardcode:

- Passwords.
- Tokens.
- API keys.
- Database credentials.
- Keycloak secrets.
- Environment-specific URLs.

Use environment variables and/or a secret manager.

Example:

```yaml
spring:
  datasource:
    url: ${DATABASE_URL}
    username: ${DATABASE_USERNAME}
    password: ${DATABASE_PASSWORD}
```

Configuration must differ by environment without changing application code.

---

## 4.7 Profiles

Use profiles carefully:

```text
application.yml
application-local.yml
application-test.yml
application-prod.yml
```

Do not create a large number of profiles for minor variations.

---

# 5. Spring Security + Keycloak

## 5.1 Authentication

Keycloak is responsible for identity and token issuance.

The backend should validate JWT access tokens.

The frontend must never implement its own authentication protocol.

---

## 5.2 Authorization

Authentication answers:

> Who are you?

Authorization answers:

> What are you allowed to do?

Use roles and/or scopes for authorization.

Example:

```text
ROLE_ADMIN
ROLE_PLAYER
ROLE_MODERATOR
```

Prefer business permissions when the domain becomes complex:

```text
player:read
player:update
fleet:dispatch
research:start
```

---

## 5.3 Never trust frontend authorization

The Vue application can hide UI elements, but that is not security.

This is insufficient:

```javascript
if (user.isAdmin) {
  showDeleteButton();
}
```

The backend must enforce:

```text
HTTP request
    |
    v
JWT validation
    |
    v
Authorization
    |
    v
Business operation
```

---

## 5.4 Token handling

Avoid storing long-lived access tokens in insecure browser storage when a safer architecture is available.

Prefer secure authentication flows supported by Keycloak and the application architecture.

Tokens must have:

- Short reasonable lifetime.
- Appropriate audience.
- Appropriate scopes/roles.
- Minimal privileges.

Never log access tokens or refresh tokens.

---

## 5.5 Service-to-service authentication

For service-to-service communication, do not forward user credentials.

Use appropriate OAuth2 client credentials or another explicitly approved service identity mechanism.

Each service should have only the permissions it requires.

---

## 5.6 Keycloak configuration

Treat Keycloak configuration as code/infrastructure where practical.

Version:

- Realm configuration.
- Clients.
- Roles.
- Scopes.
- Identity-provider configuration where safe.

Never commit production secrets.

---

# 6. REST API Standards

## 6.1 Resource-oriented URLs

Prefer:

```text
GET    /api/v1/players
GET    /api/v1/players/{id}
POST   /api/v1/players
PATCH  /api/v1/players/{id}
DELETE /api/v1/players/{id}
```

Avoid:

```text
POST /api/createPlayer
POST /api/getPlayer
POST /api/deletePlayer
```

---

## 6.2 Versioning

Use an explicit API version when the API is expected to evolve:

```text
/api/v1/players
```

Do not make breaking changes to an existing version.

---

## 6.3 Pagination

Never return an unbounded collection.

Use:

```text
GET /api/v1/players?page=0&size=20
```

For large or high-volume systems, cursor-based pagination may be preferable.

---

## 6.4 Idempotency

Operations that may be retried must be designed carefully.

Examples:

```text
POST payment
POST dispatch-fleet
POST create-order
```

For operations where duplicate execution is dangerous, support an idempotency key.

---

## 6.5 Time and dates

Use UTC internally.

Prefer ISO-8601:

```text
2026-08-25T22:30:00Z
```

Do not use server local time for business-critical calculations unless explicitly required.

---

# 7. Vue Frontend Standards

## 7.1 Component design

Components should have a clear responsibility.

Avoid giant components containing:

- API calls.
- Business rules.
- Authentication logic.
- State management.
- UI rendering.
- Formatting.

Prefer:

```text
components/
views/
composables/
services/
stores/
router/
types/
```

---

## 7.2 API communication

Do not call APIs directly from every component.

Prefer a centralized service layer:

```text
views
  |
  v
stores/composables
  |
  v
API services
  |
  v
backend
```

Example:

```text
src/services/playerService.ts
src/services/researchService.ts
src/services/fleetService.ts
```

---

## 7.3 State management

Use centralized state only when state is genuinely shared.

Do not put every local UI variable into global state.

Separate:

- Server state.
- Application state.
- UI state.

---

## 7.4 Type safety

Use TypeScript.

Avoid:

```typescript
const data: any = response.data;
```

Prefer explicit types:

```typescript
interface Player {
  id: string;
  name: string;
}
```

API contracts should have corresponding frontend types.

---

## 7.5 Error handling

The frontend must handle:

- 400 validation errors.
- 401 authentication expiration.
- 403 authorization failure.
- 404 missing resources.
- 409 business conflicts.
- 429 rate limits.
- 500 server errors.
- Network failures.

Do not display raw backend exceptions to users.

---

## 7.6 Authentication state

Centralize authentication handling.

The application should have a single source of truth for:

```text
authenticated user
roles
permissions
token state
session expiration
logout
```

Do not duplicate authentication logic across components.

---

# 8. PostgreSQL Standards

## 8.1 Schema design

Use normalized relational models by default.

Denormalize only when there is a measured reason.

Every table should have a clear ownership model.

---

## 8.2 Primary keys

Prefer UUIDs for distributed systems when appropriate.

Example:

```sql
id UUID PRIMARY KEY
```

Use database-generated UUIDs or application-generated UUIDs consistently.

Do not mix multiple identifier strategies without a reason.

---

## 8.3 Foreign keys

Use foreign keys for relationships inside the same database ownership boundary.

Do not create cross-service foreign keys.

A service must never depend on another service's database schema.

---

## 8.4 Constraints

Business invariants that belong in the database should be protected by constraints.

Use:

```sql
NOT NULL
UNIQUE
CHECK
FOREIGN KEY
```

Example:

```sql
CONSTRAINT positive_amount
CHECK (amount >= 0)
```

---

## 8.5 Indexes

Create indexes based on actual query patterns.

Every index has a cost:

- Storage.
- INSERT/UPDATE overhead.
- Maintenance.

Do not blindly index every column.

Review slow queries with:

```sql
EXPLAIN
EXPLAIN ANALYZE
```

---

## 8.6 Migrations

Never modify production schemas manually.

Use a migration tool such as:

- Flyway.
- Liquibase.

Every schema change must be represented by a migration.

Example:

```text
V1__initial_schema.sql
V2__add_player_table.sql
V3__add_research.sql
V4__add_fleet_status.sql
```

Migrations must be:

- Versioned.
- Reviewed.
- Tested.
- Reproducible.

---

## 8.7 Transactions

Transactions should be as short as practical.

Do not keep database transactions open while calling external services.

Bad:

```text
BEGIN
  update database
  call REST service
  call another REST service
COMMIT
```

Prefer:

```text
transaction
  update local state
  write outbox event
commit

publish event
```

---

## 8.8 Optimistic locking

Use optimistic locking where concurrent updates are possible.

Example:

```java
@Version
private Long version;
```

Do not assume two requests cannot update the same record simultaneously.

---

# 9. Transactional Outbox

When a database change and an event publication must remain consistent, use the Outbox pattern.

Example:

```text
BEGIN TRANSACTION

UPDATE player

INSERT INTO outbox_event (...)

COMMIT
```

A separate publisher sends the event.

This prevents:

```text
Database updated
       |
       X
Event failed
```

from leaving the system inconsistent.

Outbox records should have:

- ID.
- Event type.
- Aggregate ID.
- Payload.
- Created timestamp.
- Published timestamp/status.
- Retry metadata.

---

# 10. Concurrency and Distributed Systems

Assume that:

- Requests can be duplicated.
- Messages can be delivered more than once.
- Services can restart.
- Networks can fail.
- Database connections can disappear.
- External services can be slow.
- Multiple users can modify the same entity simultaneously.

Therefore:

## 10.1 Idempotent consumers

Consumers must safely process duplicate events.

Use an inbox/processed-event mechanism when necessary.

---

## 10.2 Retries

Retries must be bounded.

Use:

```text
exponential backoff
jitter
maximum attempts
dead-letter handling
```

Never retry indefinitely.

---

## 10.3 Timeouts

Every external call must have a timeout.

Never allow an HTTP client to wait forever.

---

## 10.4 Circuit breakers

For unstable external dependencies, consider circuit breakers.

The objective is to prevent one failing service from taking down the entire system.

---

# 11. Observability

Every production service should provide:

```text
Logs
Metrics
Health checks
Tracing
```

---

## 11.1 Structured logging

Prefer JSON/structured logs.

Include:

```text
timestamp
level
service
environment
traceId
correlationId
userId where appropriate
operation
errorCode
```

Never log:

- Passwords.
- Access tokens.
- Refresh tokens.
- Client secrets.
- Sensitive personal information.

---

## 11.2 Correlation IDs

A request crossing multiple services should be traceable.

Example:

```text
Frontend
   |
   | correlationId=ABC
   v
API Gateway
   |
   v
player-service
   |
   v
economy-service
```

The same trace/correlation context should be propagated.

---

## 11.3 Health endpoints

Expose appropriate health/readiness information.

Distinguish:

```text
liveness
readiness
```

A service can be alive but not ready to receive traffic.

---

## 11.4 Metrics

Monitor at minimum:

```text
HTTP request rate
HTTP error rate
HTTP latency
Database connection pool
Database query latency
JVM memory
JVM CPU
Garbage collection
Message processing failures
External dependency latency
```

---

# 12. Testing Strategy

Testing should exist at multiple levels.

```text
Unit tests
Integration tests
API tests
Contract tests
End-to-end tests
```

---

## 12.1 Unit tests

Test business rules without requiring:

- PostgreSQL.
- Keycloak.
- Docker.
- Network.

Unit tests should be fast.

---

## 12.2 Integration tests

Test:

- PostgreSQL integration.
- JPA mappings.
- Transactions.
- Security configuration.
- Messaging.
- External adapters.

Use realistic infrastructure where appropriate.

Testcontainers is recommended for infrastructure-dependent integration tests.

---

## 12.3 API tests

Verify:

- Status codes.
- Request validation.
- Response structure.
- Authentication.
- Authorization.
- Error responses.

---

## 12.4 Contract testing

For microservices, consider consumer-driven contract testing.

The objective is to detect:

```text
Service A expects X
Service B changes X
Production breaks
```

before deployment.

---

## 12.5 End-to-end tests

Use E2E tests for critical user journeys.

Do not attempt to cover every possible scenario with E2E tests.

Keep most business logic covered by faster tests.

---

# 13. Security

Security is mandatory at every layer.

## 13.1 Secrets

Never commit:

```text
passwords
API keys
private keys
JWT secrets
database credentials
client secrets
```

Use:

- Environment variables for basic deployments.
- Secret managers for production.

---

## 13.2 Least privilege

Every component receives only the permissions it needs.

Examples:

- Application DB user should not be PostgreSQL superuser.
- Service A should not have Service B's permissions.
- Keycloak clients should have minimal scopes.
- Admin APIs should require explicit authorization.

---

## 13.3 Database users

Do not use:

```text
postgres
```

as the application runtime user.

Create dedicated users.

Example:

```text
player_service_user
economy_service_user
research_service_user
```

Grant only required permissions.

---

## 13.4 Input security

Validate and sanitize all external input.

Never construct SQL with string concatenation.

Use:

- JPA parameters.
- Prepared statements.
- Query parameters.

---

## 13.5 Dependency security

Regularly scan dependencies for known vulnerabilities.

Keep:

- Java.
- Spring Boot.
- Node.
- Vue.
- PostgreSQL drivers.
- Keycloak integration libraries.

reasonably current and supported.

---

# 14. API Gateway

If an API gateway is used, centralize only cross-cutting concerns such as:

- Routing.
- TLS termination.
- Authentication integration.
- Rate limiting.
- Request correlation.
- Basic request policies.

Do not move business logic into the gateway.

Business logic belongs in the appropriate service.

---

# 15. Frontend/Backend Contract

The API contract is a shared boundary.

Recommended workflow:

```text
OpenAPI specification
        |
        +--> Spring Boot API
        |
        +--> Vue TypeScript client/types
        |
        +--> API tests
```

Keep OpenAPI documentation synchronized with implementation.

Breaking changes must be intentional and versioned.

---

# 16. API Compatibility

When changing an API:

### Safe changes

Usually safe:

- Adding optional response fields.
- Adding new endpoints.
- Adding optional request fields.
- Adding new resources.

### Potentially breaking

Require careful versioning:

- Removing fields.
- Renaming fields.
- Changing field types.
- Changing semantics.
- Removing endpoints.
- Making optional fields mandatory.

---

# 17. Git Standards

Use short-lived branches where practical.

Recommended:

```text
main
feature/*
fix/*
hotfix/*
chore/*
```

Commit messages should describe intent.

Good:

```text
feat: add fleet dispatch validation
fix: prevent duplicate research completion
refactor: isolate player repository
test: add concurrent fleet update tests
```

Avoid:

```text
update
changes
stuff
final
final2
fixing
```

---

# 18. Pull Requests

Every PR should be small enough to review.

A PR should explain:

```text
What changed?
Why?
How was it tested?
Any migration?
Any API change?
Any security impact?
Any operational impact?
```

Reviewers should verify:

- Architecture.
- Security.
- Tests.
- Error handling.
- Database changes.
- API compatibility.
- Observability.
- Performance where relevant.

---

# 19. CI/CD

Every PR should automatically run at minimum:

```text
Compile
Unit tests
Integration tests where appropriate
Static analysis
Dependency/security checks
Formatting/linting
```

Deployment should be automated.

Prefer:

```text
commit
  |
  v
CI
  |
  +--> build
  +--> test
  +--> security scan
  +--> package
  |
  v
artifact/container
  |
  v
deployment
```

Do not build production artifacts manually on developer machines.

---

# 20. Docker

Each service should have a reproducible container build.

Use multi-stage builds when appropriate.

The runtime image should contain only what is necessary.

Do not run applications as root unless there is a documented reason.

Configuration must be externalized.

---

# 21. Database Backup and Recovery

A backup is not enough.

The project must periodically verify that backups can actually be restored.

Define:

```text
RPO - Recovery Point Objective
RTO - Recovery Time Objective
```

Test restoration procedures.

Production database migrations must be reversible or have a documented recovery strategy where rollback is not possible.

---

# 22. Performance

Do not optimize based on assumptions.

Measure first.

Important areas:

```text
API latency
database queries
N+1 queries
connection pools
memory
CPU
network calls
frontend bundle size
```

Avoid premature optimization.

---

## 22.1 N+1 queries

Monitor ORM-generated queries.

Example problem:

```text
1 query for players
+
N queries for each player's research
```

Use appropriate:

- Fetch strategies.
- Projections.
- Explicit queries.
- Batch operations.

Do not blindly use eager loading everywhere.

---

# 23. Caching

Cache only when there is a demonstrated performance or load problem.

Define:

```text
cache key
TTL
invalidation strategy
consistency requirements
failure behavior
```

Never assume cached data is always correct.

For distributed caching, explicitly document ownership and invalidation.

---

# 24. Domain Rules

Business rules should have one authoritative implementation.

Avoid duplicating a rule in:

```text
Vue
Spring controller
Spring service
database trigger
another microservice
```

Example:

If a fleet cannot be dispatched when resources are insufficient, the authoritative rule should live in the appropriate backend/domain service.

The frontend may mirror the rule for UX, but must not be the authority.

---

# 25. Time-Dependent Systems

For systems containing:

- timers,
- production,
- cooldowns,
- research,
- resource generation,
- scheduled jobs,

do not rely on frontend timers as the source of truth.

The backend/database/domain model must calculate authoritative state.

The frontend timer is only a visualization.

Prefer storing:

```text
startedAt
duration
completedAt
```

or another deterministic representation.

---

# 26. Scheduled Jobs

Scheduled jobs must be safe when:

- The service restarts.
- The job executes twice.
- Multiple service instances run simultaneously.

Avoid assuming:

```text
@Scheduled
```

automatically provides distributed locking.

For distributed deployments use an appropriate mechanism such as:

- Database locking.
- ShedLock.
- Quartz.
- Dedicated job infrastructure.

---

# 27. Data Consistency

For every important operation, explicitly define the consistency requirement.

Examples:

```text
Strong consistency
Eventual consistency
Read-your-writes
Best effort
```

Do not accidentally introduce eventual consistency into a workflow that requires immediate consistency.

---

# 28. Architecture Decision Records

Important architectural decisions should be documented.

Example:

```text
docs/adr/
├── ADR-001-microservices-boundaries.md
├── ADR-002-keycloak-authentication.md
├── ADR-003-database-per-service.md
├── ADR-004-event-driven-communication.md
└── ADR-005-transactional-outbox.md
```

Each ADR should contain:

```text
Context
Decision
Alternatives
Consequences
Status
```

---

# 29. Documentation

Every service should have a README containing:

```text
Purpose
Responsibilities
Dependencies
Configuration
Local development
Database
API
Events
Testing
Deployment
Troubleshooting
```

Avoid documentation that only explains obvious code.

Document decisions and operational knowledge.

---

# 30. Recommended Project Structure

A possible repository structure:

```text
project/
├── services/
│   ├── player-service/
│   ├── economy-service/
│   ├── research-service/
│   └── fleet-service/
│
├── frontend/
│   └── web-app/
│
├── infrastructure/
│   ├── docker/
│   ├── keycloak/
│   ├── postgres/
│   └── observability/
│
├── contracts/
│   ├── openapi/
│   └── events/
│
├── docs/
│   └── adr/
│
├── scripts/
│
└── README.md
```

This is a recommendation, not a mandatory structure.

---

# 31. Definition of Done

A feature is not complete merely because it works locally.

Before considering a feature complete, verify:

- [ ] Business logic is implemented in the correct service.
- [ ] API contract is documented.
- [ ] Authentication is implemented where required.
- [ ] Authorization is enforced server-side.
- [ ] Input validation exists.
- [ ] Errors are handled consistently.
- [ ] Database changes use migrations.
- [ ] No cross-service database access exists.
- [ ] Unit tests cover important business rules.
- [ ] Integration tests cover infrastructure behavior where appropriate.
- [ ] API tests cover critical endpoints.
- [ ] Logs are useful and do not expose secrets.
- [ ] Metrics/health checks are appropriate.
- [ ] Configuration is externalized.
- [ ] No secrets are committed.
- [ ] API compatibility has been reviewed.
- [ ] Performance impact has been considered.
- [ ] Documentation has been updated.
- [ ] CI passes.

---

# 32. Architecture Red Flags

The following should trigger architectural review:

```text
Microservice directly querying another service's database
Controller containing business logic
Entity exposed directly through REST
Frontend being the authority for business rules
Shared mutable database tables across services
Hardcoded credentials
No API timeouts
Infinite retries
No database migrations
Production schema modified manually
Distributed transaction without documented justification
Large synchronous service chains
Global "utils" service
One microservice for every database table
One giant microservice containing the entire system
No centralized authentication
Authorization implemented only in Vue
Logging tokens/passwords
Unbounded API queries
Scheduled jobs without concurrency protection
```

---

# 33. Golden Rules

If there is uncertainty, start with these rules:

1. **The backend is authoritative for business rules.**
2. **Each microservice owns its data.**
3. **Never share database tables between services.**
4. **Keycloak handles identity; services enforce authorization.**
5. **Never trust the frontend for security.**
6. **Never expose persistence entities directly through APIs.**
7. **Every database change goes through a migration.**
8. **Every external call has a timeout.**
9. **Retries must be bounded and safe.**
10. **Distributed operations must be designed for duplicate execution.**
11. **Events must be versioned and consumers should be idempotent.**
12. **Use UTC for distributed system timestamps.**
13. **Do not log secrets or tokens.**
14. **Test business rules independently of infrastructure.**
15. **Measure performance before optimizing.**
16. **Prefer explicit architecture over accidental coupling.**
17. **Keep services focused on business capabilities.**
18. **Document important architectural decisions.**
19. **Automate build, test, security checks and deployment.**
20. **When breaking a rule, document why.**

---

# 34. Recommended Technology Responsibilities

| Technology                    | Primary responsibility                      |
| ----------------------------- | ------------------------------------------- |
| Spring Boot                   | Backend services and application APIs       |
| Spring Security               | Backend security integration                |
| Keycloak                      | Identity, authentication and token issuance |
| Vue                           | User interface                              |
| TypeScript                    | Frontend type safety                        |
| PostgreSQL                    | Relational persistence                      |
| Flyway/Liquibase              | Database schema migrations                  |
| OpenAPI                       | API contract/documentation                  |
| Docker                        | Reproducible runtime environments           |
| CI/CD                         | Automated validation and deployment         |
| OpenTelemetry                 | Distributed tracing/telemetry               |
| Prometheus-compatible metrics | Metrics                                     |
| Structured logging            | Operational diagnostics                     |

Technologies may be replaced, but responsibilities should remain clearly separated.

---

# 35. Final Architectural Rule

The most important rule for this project is:

> **Business capabilities define the architecture; technologies implement it.**

Do not allow Spring Boot, Vue, PostgreSQL, Keycloak or any other technology to dictate business boundaries.

The system should remain understandable if one implementation technology is replaced.

A healthy architecture should make it possible to answer these questions quickly:

```text
Which service owns this business rule?
Which service owns this data?
Which API exposes this capability?
Who is allowed to call it?
What happens if the dependency fails?
Can the operation be retried safely?
How is the operation observed?
How is the data migrated?
How is the feature tested?
How is the feature recovered in production?
```

If those questions cannot be answered clearly, the architecture needs clarification before adding more complexity.
