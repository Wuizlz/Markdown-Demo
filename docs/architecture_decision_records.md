# Architecture Decision Records (ADRs) — Campus Event Hub

This document records the key architectural decisions for the **Campus Event Hub** internal university web system.

- **Project**: Campus Event Hub
- **Owner**: Engineering Team (2–4 engineers)
- **Last updated**: 2026-02-04

---

## ADR Format

Each ADR uses this structure:
- **Status**: Proposed | Accepted | Superseded
- **Context**: What forces/constraints led to this decision
- **Decision**: The selected option
- **Alternatives Considered**: Options not chosen
- **Consequences**: Tradeoffs and impacts (positive/negative)

---

## ADR-001 — System Roles & Communication

- **Status**: Accepted
- **Date**: 2026-02-04

### Context
Campus Event Hub supports:
- Student organization leaders submitting events for review.
- Staff administrators approving/rejecting events.
- Students browsing and searching approved upcoming events.

Constraints:
- Internal university system (not public commercial scale).
- Low to moderate concurrency; no strict real-time requirements.
- Small team and limited operational budget.

### Decision
Use a **Client–Server** architecture:
- A browser-based web client communicates with a backend server over HTTPS.
- The server handles authentication, validation, authorization (basic role checks), and data persistence.
- The client renders submission, browsing/search, and admin review experiences.

### Alternatives Considered
1. **Event-Driven Architecture (EDA)** with message broker and event consumers.

### Why Not the Alternative
- EDA adds operational and conceptual overhead (brokers, consumers, retries, eventual consistency).
- Current requirements are primarily CRUD + review workflow + search, which are naturally request/response.
- No need for complex cross-component reactions at this scope.

### Consequences
**Positive**
- Simple mental model and debugging path.
- Clear security boundary for internal auth.
- Matches acceptance criteria (fast responses, immediate confirmations).

**Negative**
- If future features require many independent integrations (e.g., multiple downstream systems), EDA might be revisited.

---

## ADR-002 — Deployment & Evolution Strategy

- **Status**: Accepted
- **Date**: 2026-02-04

### Context
The system is maintained by a small team with limited ops resources. Expected load is modest. Maintainability is a core requirement:
- Adding features (e.g., email reminders, featured events) should not require major refactoring.
- Changes to one feature should not destabilize unrelated features.

### Decision
Deploy as a **Monolith (Modular Monolith)**:
- Single backend deployable containing all business capabilities.
- Internally structured into modules to preserve boundaries and maintainability.
- Scale using vertical scaling first; optionally horizontal replicas if needed.

### Alternatives Considered
1. **Microservices** (multiple independently deployed services).

### Why Not the Alternative
- Microservices increase operational overhead: service coordination, distributed tracing, multiple pipelines, deployment/versioning complexity.
- The domain is cohesive and small; splitting early is likely to slow delivery and increase failure modes.

### Consequences
**Positive**
- Lowest operational burden; easiest CI/CD and incident response.
- Clear ownership and end-to-end testing is simpler.

**Negative**
- Requires discipline to prevent “big ball of mud” growth; mitigated by modular boundaries and testing.

---

## ADR-003 — Code Organization & Dependency Direction

- **Status**: Accepted
- **Date**: 2026-02-04

### Context
We want:
- High cohesion within features (submission, discovery, review).
- Low coupling across features to satisfy maintainability acceptance criteria.
- A structure that supports easy onboarding and future additions.

### Decision
Use **Feature-Based Architecture (Vertical Slices)**:
- Organize code by business capability:
  - `event-submission`
  - `event-discovery`
  - `event-review-admin`
  - `shared` (auth, db utilities, common types)
- Within each feature, keep what it needs (routes/controllers, services, validators, repositories, tests).
- Enforce dependency direction where possible (domain/service logic not depending on UI concerns).

### Alternatives Considered
1. **Layered Architecture** (controllers → services → repositories → models), organized primarily by technical layer.

### Why Not the Alternative
- Layered-only structures often cause changes to span many folders for a single feature update.
- Feature-based organization better localizes change and reduces accidental coupling for small teams.

### Consequences
**Positive**
- Changes are naturally scoped to the feature being modified.
- Easier to add new capabilities without reorganizing large portions of the codebase.

**Negative**
- Requires conventions to avoid duplicated patterns across modules; mitigated by a well-defined `shared` area and templates.

---

## ADR-004 — Data & State Ownership

- **Status**: Accepted
- **Date**: 2026-02-04

### Context
Core workflow relies on a single **Event** entity with a lifecycle:
- `submitted` → `approved` or `rejected`
Visibility rule:
- Only **approved** events are visible to general student browsing/search.

Search/filter requirements:
- Filter by date and category.
- Results should load within a few seconds under expected load.

### Decision
Use a **Single Shared Database** as the system of record:
- Prefer a relational DB (e.g., PostgreSQL) to support filtering, indexing, and integrity constraints.
- Keep event status and visibility rules in the same database to ensure consistent reads for browsing and review actions.

### Alternatives Considered
1. **Database per Service** (implies multiple services with separate databases).

### Why Not the Alternative
- Database-per-service makes most sense with microservices (not chosen).
- Increases data duplication and consistency complexity, often pushing toward asynchronous/event-driven integration.
- Overkill for current size and load.

### Consequences
**Positive**
- Strong consistency for approval visibility.
- Simpler schema management and backups.
- Straightforward indexing for search performance.

**Negative**
- Shared schema requires careful migrations and change management; mitigated by migration tooling and review.

---

## ADR-005 — Interaction Model

- **Status**: Accepted
- **Date**: 2026-02-04

### Context
Acceptance criteria emphasize:
- Immediate validation errors on submission and no save when invalid.
- Confirmation message after successful submission.
- Browse/search results displayed within a few seconds.
- Approve/reject updates should immediately affect visibility.

### Decision
Use a primarily **Synchronous** interaction model:
- Form submissions and admin actions complete in a single request/response.
- Browse/search is request/response with indexed queries for performance.

### Alternatives Considered
1. **Asynchronous-first** processing (queues/workers for submission, approvals, or searches).

### Why Not the Alternative
- Async-first introduces eventual consistency and “processing pending” states.
- Requires extra infrastructure (queue, workers, retry policies) not justified by the current scope.

### Consequences
**Positive**
- Predictable behavior aligned with requirements.
- Simpler error handling and user feedback.

**Negative**
- If future features add heavy processing (e.g., email reminders, scheduled digests), those should be implemented as background jobs **in addition to** (not replacing) synchronous core flows.

---

## Appendix — Decision Summary

| Dimension | Decision |
|---|---|
| System Roles & Communication | Client–Server |
| Deployment & Evolution | Modular Monolith |
| Code Organization | Feature-Based (Vertical Slices) |
| Data Ownership | Single Shared Database |
| Interaction Model | Synchronous |
