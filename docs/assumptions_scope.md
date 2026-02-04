## Assumptions & Scope — Campus Event Hub

### Assumptions
- **Internal university system**: Only intended for university-affiliated users (students, org leaders, staff).
- **User volume & roles**:
  - Hundreds of students browsing/searching events.
  - Dozens of event organizers submitting events.
  - A small number of staff administrators reviewing/approving events.
- **Traffic profile**: Low to moderate concurrent usage (typical campus peaks around lunch/evenings).
- **Availability needs**: No strict real-time requirements and no high-availability/SLA guarantees required.
- **Team & operations**: Small engineering team (2–4 engineers) with limited operational bandwidth.
- **Hosting**: Cloud hosting is available, but **budget and operational resources are limited** (prefer simpler deployments).
- **Authentication**: Users can be authenticated via an internal university login method (e.g., SSO) and assigned one of the three roles listed above.
- **Event lifecycle**: Events move through statuses: `submitted → approved` or `submitted → rejected`. Only approved events are visible to students.
- **Data expectations**: Events include at minimum title, date, time, location, description; optional metadata like category/tags may exist for filtering.
- **Performance target**: Search/browse pages should return results within a few seconds under expected load.

### In Scope
- Event submission by student organization leaders with validation and confirmation messaging.
- Admin review workflow (view submitted events, approve/reject).
- Event discovery for students:
  - Browse upcoming events
  - Search events
  - Filter by date and category
  - View event detail page
- Basic maintainability expectations:
  - New features can be added in future semesters without major refactoring.
  - Changes to one feature should not break unrelated features.

### Out of Scope
- Native mobile applications (iOS/Android).
- Public APIs for external partners or third-party integrations.
- Real-time chat, messaging, or live streaming features.
- Complex role-based permission systems beyond the three stated roles.
- Advanced analytics, personalization, or recommendation engines.
- Enterprise-grade high availability, multi-region failover, or strict uptime SLAs.
