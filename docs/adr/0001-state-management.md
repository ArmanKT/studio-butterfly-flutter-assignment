# ADR 0001: State Management Choice and Responsive Layout Strategy

* **Status:** Approved
* **Date:** 2026-07-10
* **Author:** Arman

## Context

The Formwork SMS Console requires:
1. Decoupling business logic from widgets to ensure clean, maintainable patterns.
2. Robust multi-tenant state isolation: changing tenants must immediately wipe and refresh all logs, billing details, and API configurations.
3. Managing asynchronous events, loading states, rate-limiting (429) cooldowns, and automatic auth token refreshes.
4. Seamlessly scaling across mobile (360px) and desktop (1400px) widths.

## Decision

We chose **BLoC (Business Logic Component)** as our state management framework and implemented a **LayoutBuilder Adaptive Shell** for responsiveness.

### 1. State Management (BLoC)

* **Event-Driven Architecture:** BLoC provides a strict structure where the UI dispatches events and BLoC emits immutable states, enforcing unidirectional data flow.
* **Multi-Tenant Scoping:** By subscribing the `MessageHistoryBloc` and `CostBreakdownBloc` to the `TenantBloc`'s stream in their constructors, they automatically react to tenant switch events, clear cache, and reload state, guaranteeing zero cross-tenant state leaks.
* **Context-Free Testing:** BLoCs do not depend on the widget context, allowing us to inspect states and test business logic easily in unit tests.
* **Separation of Concerns:** Business logic is entirely contained within BLoC classes, keeping the widgets purely representational.

### 2. Responsive Layout (LayoutBuilder Adaptive Shell)

* **Breakpoint:** We defined a breakpoint of `800px` to partition mobile/tablet and desktop screens.
* **Mobile (< 800px):** Employs a `DefaultTabController` with two tabs (Console: SMS form & costs; Logs: paginated sent history). This prevents vertical layout overcrowding and keeps scrolling clean on small screens.
* **Desktop (>= 800px):** Renders a side-by-side two-column grid. Left column holds the input form and monthly billing total/table; right column displays a full-height paginated transaction list.

---

## Alternatives Considered

### 1. Riverpod
* *Pros:* Compile-time safety and easy state isolation using provider overrides.
* *Cons:* Non-standard syntax and reliance on global provider declarations. For teams accustomed to standard reactive Streams or BLoC, Riverpod introduces unnecessary complexity.

### 2. Provider (InheritedWidget Wrapper)
* *Pros:* Simple, native feeling.
* *Cons:* Depends on the widget tree's `BuildContext` to lookup state, making it prone to runtime `ProviderNotFoundException` errors. It also lacks BLoC's explicit event-state audit trails.

---

## Consequences

* **Testability:** State streams can be easily tested using standard stream assertions and assertions on emitted states.
* **Correctness:** Zero-leak multi-tenancy is guaranteed because the state layer resets itself automatically on tenant switches.
* **Aesthetics:** The UI is clean, responsive, and conforms to Material 3 guidelines.
