# ADR 0001: State Management and Responsive Layout Decisions

* **Status:** Approved
* **Date:** 2026-07-10
* **Author:** Arman

## Context

The Formwork SMS Console needed to satisfy these conditions:
1. **Clean Separation:** Keep business logic out of the UI widgets to make the code easy to maintain.
2. **Tenant Isolation:** When switching tenants, the app must immediately clear the logs, cost breakdown, and tokens of the old tenant to prevent data leaks.
3. **Error & Loading States:** Cleanly handle loading indicators, API errors, rate-limiting (429) wait times, and token refreshes.
4. **Adaptive UI:** Look great on a small mobile screen (360px) and a large desktop screen (1400px).

## Decisions Made

We decided to use **BLoC (Business Logic Component)** for managing state, and a **LayoutBuilder** for the responsive layout.

### 1. Why BLoC?

* **Strict Rules:** BLoC forces a clear flow. The UI sends *events*, and the BLoC responds with *states*.
* **Tenant Safety:** We linked the history and cost BLoCs directly to the `TenantBloc` stream. When the tenant changes, the BLoCs automatically catch the event, wipe the old data, and fetch the new tenant's data. This guarantees no data leaks.
* **Easy Testing:** BLoCs do not depend on the UI code, so we can test all business logic easily with simple unit tests.

### 2. Why LayoutBuilder?

* **Breakpoint:** We chose `800px` as our screen width breakpoint.
* **Mobile View (< 800px):** We show a two-tab view (Console tab and Logs tab). This keeps the screen clean and easy to use on small phones.
* **Desktop View (>= 800px):** We show a side-by-side grid layout. The left column holds the form and cost table, and the right column shows the scrollable message logs list.

---

## Other Options We Rejected

### 1. Riverpod
* *Pros:* Very safe and easy to use.
* *Cons:* Uses a non-standard syntax that can be difficult for teams who are already familiar with standard streams or BLoC patterns. We chose BLoC to keep things standard and easy to read.

### 2. Provider
* *Pros:* Simple and built-in.
* *Cons:* It relies on the widget context to find states. This can cause runtime errors if a developer tries to read a provider from a widget that does not have access to it. It also lacks BLoC's strict event-state flow.

---

## Consequences

* **Better Code Quality:** The code is modular, fully testable, and robust.
* **Tenant Security:** All tenant switching is completely secure with no caching leaks.
* **Responsiveness:** The app automatically resizes and looks excellent on both mobile and desktop screens.
