# Tech Stack Decision Records (TSDRs) — Campus Event Hub

This document records **technology stack** decisions for the **Campus Event Hub** internal university web system.
It complements the architecture ADRs by specifying concrete tools and platforms.

- **Project**: Campus Event Hub
- **Owner**: Engineering Team (2–4 engineers)
- **Last updated**: 2026-02-08

---

## Record Format

Each record includes:
- **Status**: Proposed | Accepted | Superseded
- **Context**: Constraints and needs
- **Decision**: Selected technology
- **Alternatives Considered**: Plausible options not chosen
- **Consequences**: Tradeoffs and impacts

---

## TSDR-001 — Primary Language

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
The team needs a stack that is:
- Fast to develop for a small team
- Easy to hire/hand off for typical campus IT environments
- Suitable for web API + web UI development with strong maintainability

### Decision
Use **TypeScript** as the primary language for application code.

### Alternatives Considered
1. Java (Spring Boot)
2. Python (Django/FastAPI)

### Why Not the Alternatives
- Java: excellent for large enterprise systems, but higher ceremony for a small team and slower iteration for this scope.
- Python: strong productivity, but weaker compile-time guarantees compared to TypeScript for a growing UI + API codebase.

### Consequences
**Positive**
- Shared types between frontend and backend reduce integration bugs.
- Strong ecosystem for web development and tooling.

**Negative**
- Requires agreed conventions (linting/formatting) to avoid style drift.

---

## TSDR-002 — Backend Framework

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
The backend must support:
- Event submission with validation
- Admin review/approve/reject
- Fast search/filter queries
- Basic role checks (student, organizer, admin)
Maintainability is critical and the team is small.

### Decision
Use **NestJS (Node.js + TypeScript)** for the backend API.

### Alternatives Considered
1. Express.js
2. Spring Boot

### Why Not the Alternatives
- Express.js: lightweight but easier to become inconsistent without strong structure; more “design it yourself.”
- Spring Boot: robust but adds operational/coding overhead not needed for the current scale.

### Consequences
**Positive**
- Clear module structure, DI, validation patterns, and testing utilities.
- Improves consistency across endpoints as the app grows.

**Negative**
- Slight learning curve if the team is unfamiliar with NestJS conventions.

---

## TSDR-003 — Frontend Framework

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
The UI is not the focus of this assignment, but the system requires:
- Submission forms with validation feedback
- Browsing/search pages with filters
- Admin dashboard for review actions

### Decision
Use **React** with **Next.js** for the web frontend.

### Alternatives Considered
1. Plain React + Vite
2. Server-side templates (e.g., Thymeleaf, Django templates)

### Why Not the Alternatives
- React + Vite: perfectly fine, but Next.js gives a more “batteries included” structure for routing, auth integration, and deployments.
- Server-side templates: simpler at first, but tends to slow UI iteration and can blur concerns for a growing product.

### Consequences
**Positive**
- Strong ecosystem, maintainable component structure, and predictable routing.
- Flexible: can be purely client-rendered or add server rendering later if needed.

**Negative**
- Adds framework conventions; requires lightweight team standards (folder structure, components, hooks, etc.).

---

## TSDR-004 — Database

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
Core requirements need:
- Reliable persistence for event lifecycle states
- Filtering by date/category and retrieving upcoming events quickly
- Straightforward migrations and data integrity

### Decision
Use **PostgreSQL** as the primary database.

### Alternatives Considered
1. MySQL
2. NoSQL (MongoDB)

### Why Not the Alternatives
- MySQL: also valid, but PostgreSQL provides strong indexing, JSON support, and full-text capabilities that are useful for search.
- MongoDB: flexible schema, but this domain is well-structured; relational constraints help correctness and reporting.

### Consequences
**Positive**
- Strong consistency and relational modeling for events, categories, and statuses.
- Excellent support for indexing and query performance.

**Negative**
- Requires migration discipline; mitigated with migration tooling and reviews.

---

## TSDR-005 — Data Access Layer (ORM)

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
A small team needs:
- Safe, readable queries
- Migrations
- Type-safe data models shared with TypeScript

### Decision
Use **manual SQL** for database access and migrations.

### Alternatives Considered
1. PrismaORM
2. Knex.js (query builder) + manual SQL migrations

### Why Not the Alternatives
- PrismaORM: workable, but type safety and DX can be less predictable depending on patterns used.

### Consequences
**Positive**
- Maximum control & performance: You can hand-write exactly the query you want (joins, CTEs, full-text search tuning, index-friendly patterns) and optimize it precisely.

- Minimal abstraction & fewer dependencies: No ORM magic—your DB logic is explicit, predictable, and doesn’t require learning/maintaining an extra framework layer.

**Negative**
- More maintenance risk as the schema evolves: Renames/column changes can break scattered SQL at runtime, and there’s no type-safe safety net to catch mistakes early.

- More manual responsibility for safety/consistency: You must consistently parameterize queries, manage transactions, handle migrations, and avoid duplicated query logic—easy to slip up on a small team

---

## TSDR-006 — Search & Filtering Strategy

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
Students need fast results “within a few seconds,” with filters:
- Date range
- Category
- Text search (title/description)

Expected load is modest.

### Decision
Use **PostgreSQL indexes + full-text search (FTS)** for search and filtering.
- Add indexes on: `status`, `start_datetime`, `category_id`
- Use FTS (or `ILIKE` initially, then FTS) for title/description search

### Alternatives Considered
1. Elasticsearch/OpenSearch
2. Dedicated search service (Algolia)

### Why Not the Alternatives
- Elasticsearch/OpenSearch: operational overhead and cost not justified for modest internal usage.
- Algolia: great UX, but introduces external dependency and cost; also unnecessary at this scale.

### Consequences
**Positive**
- Simple ops (one database) and adequate performance for the stated user volume.
- Easy path to upgrade later if search becomes more complex.

**Negative**
- If search features expand significantly (ranking, synonyms, analytics), a dedicated search engine may be needed later.

---

## TSDR-007 — Hosting & Deployment

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
Constraints include limited budget and limited ops capacity. The system is internal and does not require strict HA.

### Decision
Deploy as a **single containerized web app** plus a **managed PostgreSQL** database.
- App deployed on a simple platform that supports Docker (e.g., university VM, or a managed app platform).
- Database hosted as a managed service when available.

### Alternatives Considered
1. Kubernetes
2. Self-managed database on the same VM

### Why Not the Alternatives
- Kubernetes: heavy operational overhead for the project scope and team size.
- Self-managed DB on the same VM: reduces cost but increases backup/maintenance burden and risk.

### Consequences
**Positive**
- Low operational burden; clear upgrade path (scale app replicas if needed).
- Managed DB improves reliability and simplifies backups.

**Negative**
- Some platform lock-in depending on hosting choice; mitigated by Docker-based deployment portability.

---

## TSDR-008 — Authentication & Authorization

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
Internal university system with known user types:
- Students
- Student organization leaders
- Staff administrators

### Decision
Use **University SSO via OIDC (OpenID Connect)** when available.
- Map identity claims/groups to the three roles required by scope.
- Keep authorization simple (role checks at endpoint/service boundaries).

### Alternatives Considered
1. Local username/password accounts
2. SAML-only integration

### Why Not the Alternatives
- Local accounts: adds password management risk and support overhead; unnecessary for internal systems with SSO.
- SAML-only: can work, but OIDC tends to integrate more smoothly with modern web stacks; use SAML only if campus IdP requires it.

### Consequences
**Positive**
- Strong security posture and reduced account support overhead.
- Roles can align with existing campus identity management.

**Negative**
- Depends on campus IdP availability and configuration; requires coordination with IT.

---

## TSDR-009 — Background Jobs (Future-Friendly)

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
Current scope is synchronous CRUD + review + search.
Future features mentioned include:
- Email reminders
- Featured events
These may require scheduled or background processing.

### Decision
Adopt a **lightweight background job approach**:
- Start with **scheduled tasks** (cron-style) within the app for simple reminders (if/when added).
- If load or reliability needs increase, add a queue-backed worker (e.g., Redis + BullMQ) later.

### Alternatives Considered
1. Queue/workers from day one (Redis + BullMQ)
2. Cloud-native workflow services

### Why Not the Alternatives
- Queue/day-one: extra infrastructure and failure modes not needed until the feature exists.
- Cloud workflow services: adds cost and vendor-specific ops for a small internal system.

### Consequences
**Positive**
- Keeps current architecture simple while preserving a clear upgrade path.
- Avoids premature infrastructure.

**Negative**
- Cron-in-app jobs need care in multi-replica deployments (ensure single execution); mitigated by DB locks or running jobs in one designated worker process.

---

## TSDR-010 — CI/CD, Quality Gates, and Observability

- **Status**: Accepted
- **Date**: 2026-02-08

### Context
Small teams benefit from automation to prevent regressions and keep changes safe.

### Decision
Use:
- **GitHub Actions** for CI (tests, lint, typecheck) and CD (deploy)
- **Prettier + ESLint** for formatting/linting consistency
- **Jest** for unit tests and **Playwright** for basic end-to-end testing (smoke flows)
- **Structured logging** (JSON logs) and a hosted error tracker (e.g., Sentry) if permitted by IT

### Alternatives Considered
1. Jenkins-based CI
2. Minimal CI (manual deployments)

### Why Not the Alternatives
- Jenkins: flexible but heavier to maintain for small teams.
- Minimal CI: increases regression risk and slows delivery over time.

### Consequences
**Positive**
- Consistent quality checks and safer changes across semesters.
- Faster troubleshooting with logs and error reporting.

**Negative**
- Requires initial setup time; pays off quickly as the codebase grows.

---

## Appendix — Stack Summary (Current Target)

- **Frontend**: React + Next.js
- **Backend**: NestJS (Node.js + TypeScript)
- **Database**: PostgreSQL
- **ORM/Migrations**: Raw SQL
- **Search**: PostgreSQL indexes + full-text search
- **Hosting**: Dockerized app + managed Postgres
- **Auth**: University SSO via OIDC (preferred)
- **CI/CD**: GitHub Actions
- **Testing**: Jest + Playwright (smoke/E2E)
- **Observability**: Structured logs + optional error tracking
