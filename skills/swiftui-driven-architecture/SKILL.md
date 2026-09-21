---
name: swiftui-driven-architecture
description: >-
  Build and refactor SwiftUI apps using an Apple-frameworks-only, environment-injected
  architecture: @Observable screen models that take dependencies on load methods (not
  init), protocol seams published with @Entry (defaulting to live implementations),
  SwiftData aggregate roots, .task-driven async lifecycles, and wire-shape JSON mock
  services. Use when adding a screen, designing state management or dependency
  injection, writing tests/previews, or migrating an existing app away from
  singletons, Combine-based MVVM, or third-party state containers (TCA, etc.).
---

# SwiftUI-Driven Architecture

The premise: **SwiftUI is the framework.** No Combine publishers, no coordinator
objects, no third-party state containers, no external dependencies. The entire
dependency surface is a few small protocols, injected through the SwiftUI
environment, so the same views run in production, previews, unit tests, and UI
tests. This skill encodes the patterns, the hard rules, and a phased procedure
for integrating the architecture into an existing app.

Canonical reference implementation: the OnBoard repo (`README.md`,
`CONTRIBUTING.md`, and the feature folders under `OnBoard/`). Cite those files
when the user wants a concrete, working example of any pattern below.

## When to use this architecture

- Greenfield SwiftUI app, or an existing app being migrated away from
  singleton/global dependencies, `ObservableObject`/`@Published` MVVM, or a
  third-party state container.
- The value is platform primitives taught directly: granular `@Observable`
  tracking, environment-based DI, SwiftData, structured task lifecycles.
- **Fit-check gate**: if the app's requests need cross-cutting concerns
  (auth, retry, caching, per-request analytics), invert the injection from the
  start — make the API client itself the protocol injected through the
  environment (`@Entry var api: any MyAPI`), with the transport a detail of its
  live implementation. Do not retrofit this later; deciding it first avoids
  rework.

## Core patterns

### 1. One `@MainActor @Observable` screen model per screen

```swift
@MainActor
@Observable
final class NearbyModel {
    var failure: String?        // errors surfaced, never thrown to views
    var isLoading = false
    var stops: [Stop] = []      // kept on refresh failure → stale rows + banner
    init() {}                   // takes NOTHING
}
```

- `init()` takes no dependencies. Dependencies arrive as parameters on
  load/mutate methods (`loadStops(network:latitude:longitude:)`), so a view
  writes `@State var model = NearbyModel()` and a test writes `NearbyModel()`
  with no container or factory.
- Errors become `failure = String(describing: error)`, not thrown. Swallow only
  `CancellationError`.
- Keep the previous rows on a failed refresh so the view shows stale data with
  a failure banner instead of an empty screen.

### 2. Protocol seams, published with `@Entry`, defaulting to live

```swift
// NetworkDependency.swift
extension EnvironmentValues {
    @Entry var network: NetworkProtocol = LiveNetwork()
}
```

- Model each dependency as a small protocol with one live implementation and no
  globals. **Rule of need**: if you can't name a second implementation you'd
  actually want (mock, preview stub, cache-decorated), you don't need the
  protocol yet.
- The `@Entry` default is the live implementation, so views and previews render
  with zero wiring; tests/previews override exactly what they need.
- The app entry point is the **composition root**: the only place that decides
  which implementations exist. Everything downstream reads an abstraction.

### 3. Load in `.task`/`.task(id:)`, never in init or factories

```swift
.task(id: location.coordinate) {
    guard let coordinate = location.coordinate else { return }
    await model.loadStops(network: network, latitude: coordinate.latitude, ...)
}
```

- SwiftUI owns the async lifetime and cancels on `id` change.
- Debounced search: bind `.searchable` to `@State`, load from
  `.task(id: query)`, debounce in-model with `try? await Task.sleep(for:
  .milliseconds(400))` plus `guard !Task.isCancelled` checks.
- **Cancellation guard on the loading flag**: `.task(id:)` starts the
  replacement task *before* cancelling the old one, so a cancelled load must not
  clobber the replacement's `isLoading = true`:

  ```swift
  isLoading = true
  defer {
      if !Task.isCancelled { isLoading = false }
  }
  ```

- The live transport maps `URLError.cancelled` to `CancellationError` so
  models see one cancellation type:

  ```swift
  do { return try await URLSession.shared.data(for: request) }
  catch URLError.cancelled { throw CancellationError() }
  catch { throw error }
  ```

### 4. SwiftData as an injected dependency, one aggregate root per feature

- The app entry point builds the `ModelContainer` once; views read
  `@Environment(\.modelContext)` and **hand the context into model methods**
  (`toggle(_:name:lines:context:)`) — the model stays storage-agnostic, no
  singleton context.
- Persist each feature's collection as a single `@Model` aggregate with a
  cascading relationship (e.g. `StoredFavorites` → `[Favorite]`), created on
  demand on first write; remove is a no-op when the aggregate is absent.
- Keep display invariants (sorting) in the model; the caller owns the save
  lifecycle (live app: autosave; tests: explicit `context.save()`).
- Container-open failure policy is a **written-down product decision**: fail
  fast (`fatalError`) when the app is useless without persistence; catch and
  rebuild the container instead when the store can be recreated/migrated.
- Never cache `container.mainContext` — it is computed and vends fresh
  contexts.

### 5. Presentation on the domain type

Display logic (icons, labels, formatted dates/distances) lives in computed
properties on the value types via `Type+Feature.swift` extensions next to their
consumers, shared across screens instead of duplicated per view.

### 6. Feature folders over type folders

A screen's model, view, and presentation extensions live together; adding a
feature is adding a folder, deleting one removes everything it owns. Only
cross-cutting infrastructure (`Network/`, `Location/`, `Api/`) and shared UI
(`DesignSystem/`) sit outside.

### 7. Design system extraction rule

Shared UI components (`StatusPill`, button styles, `MessageScreen`,
`UnavailableScreen`, `LoadingIndicator`) live in `DesignSystem/`, one component
per file, each with a `#Preview`. View structs stay feature-local until the
pattern shows up on **two or more screens** — then extract. Prefer extending an
existing component over adding a near-duplicate. Design tokens are asset-catalog
colorsets with generated symbols (`.ink`, `.panel`, …); no hand-written `Color`
extensions.

## Mock and test infrastructure

**A mock's job is fidelity of the bytes, not of the data model.**

- Fixtures are multiline JSON strings in the endpoint's **wire shape**, keyed by
  what the request looks up (`departuresByAreaId`, `stopGroupsByName`). Paste a
  captured response verbatim. Never configure the mock with hand-built API model
  values — that makes it a second, drifting implementation of the endpoint.
- The serving path never decodes or re-encodes: pick a string by key, join into
  the response envelope, serve `Data(body.utf8)`. The model under test then
  runs its real production `Codable` decode on exactly the fixture bytes — a
  broken fixture surfaces as a model failure, which is where you want it. This
  matters in practice: an app whose fixtures drifted from the real wire shape
  passed every test while every live response failed to decode.
- Resolve moving parts once at creation: relative timestamp markers
  (`"now"`, `"now±n"` minutes) become absolute timestamps when the service is
  built. Validate every fixture loudly at the same moment — a malformed one
  traps with the fixture named.
- Dictionary fixtures are unordered: give the served result an explicit,
  documented order, and document deviations from the real API.
- Parse request paths with small regex captures
  (`url.path.firstMatch(of: #/departures/([^/]+)/#)`) instead of
  split-and-index arithmetic.
- Keep a bare `MockNetwork` (handler registration + `TestableRequest`
  recording, mutex-guarded for actor-independence) only for request-shape
  assertions and invalid-JSON tests. A preview wired to a handler-less
  `MockNetwork` on a screen with a `.task` load shows `NoResponseConfigured` —
  use the fixture-based mock service for previews that need data.

Test conventions:

- Swift Testing (`@Test`, `#expect`); model tests are `@MainActor` and
  construct `Model()` directly, injecting the mock through the load method.
- Prefer `== []` over `isEmpty` in expectations for better failure output; rely
  on synthesized `Equatable`/`Hashable` on value types (never custom `==`
  keyed on `id` alone — use `Dictionary<id, value>` or `firstIndex` predicates).
- `@Model` classes: `==` is **object identity**, not memberwise. Compare value
  snapshots — small `Equatable` structs, not tuples (tuples don't conform to
  `Equatable`).

## Hard rules (each backed by a real failure mode)

1. **No `ObservableObject`/`@Published`** — `@Observable` gives granular
   tracking; a screen re-renders only for properties its body reads.
2. **Never load in a model's `init`, a view's `init`, or a factory** — use
   `.task`/`.task(id:)` so SwiftUI owns cancellation.
3. **Never create `State` manually** (`State(initialValue:)`, writing `_state`
   in init) — declare `@State` with an inline default expression (optionally a
   private `static` factory); inits configure only non-`@State` properties.
4. **Never give a view a secondary init just so previews can inject
   dependencies** — the default `@State` initializer expression still runs in
   the preview process and fires real, failing requests. Use
   `@Previewable @State` in the `#Preview` block and publish with
   `.environment(...)`/`.modelContainer(...)`.
5. **Never `.onChange(of:) { Task { ... } }` for debounced search** — unstructured
   tasks race and overwrite results out of order. Use `.task(id: query)`.
6. **No singletons or global containers** — the environment is the composition
   root's delivery mechanism.
7. **Never hand-build API model values in a mock** — wire-shape JSON only.
8. **Never compare `@Model` instances with `==` for field equality** — compare
   value snapshots.
9. **A view reading `@Environment(\.modelContext)` must always get a
   `.modelContainer(...)`** in previews — it traps otherwise.
10. **User-facing in-app text stays English** even when API data is another
    language (system permission prompts may localize).

## Integrating into an existing app

Apply in this order, one seam at a time; each phase leaves the app working.

**Phase 0 — Fit-check and decide the injection level.** Inventory the app's
dependencies (network, storage, location). If cross-cutting request concerns
dominate, inject the API client as the protocol (`@Entry var api: any MyAPI`)
instead of the transport; otherwise inject the transport. Decide the
container-failure policy (fail fast vs. rebuild) and write it down.

**Phase 1 — Extract one protocol seam.** Pick the worst dependency (usually
networking). Define a minimal protocol mirroring the calls actually made, with
one live implementation forwarding to the existing code. No globals. If no
second implementation is nameable, skip the protocol.

**Phase 2 — Publish with `@Entry`, default to live.**
`@Entry var network: NetworkProtocol = LiveNetwork()`. Existing call sites keep
working while you migrate them to `@Environment(\.network)` gradually; views
render without wiring, so previews don't break mid-migration.

**Phase 3 — Migrate one screen to a screen model.** Choose a single view as
the reference template: create the `@MainActor @Observable` model with an empty
init, `failure`/`isLoading`/rows state, a `loadX(network:...)` method that
surfaces errors as `failure`, and trigger it from `.task`/`.task(id:)` with the
cancellation-guarded `defer`. This screen becomes the exemplar for the rest.

**Phase 4 — Storage seam.** Move `ModelContainer` construction to the app entry
point (`.modelContainer(...)`), define one aggregate root per feature, pass
`ModelContext` into model methods, create the aggregate on demand, keep display
invariants in the model.

**Phase 5 — Test infrastructure.** Build a feature-specific mock service
configured by wire-shape JSON fixtures (validated at creation, time-relative
markers resolved once), plus the bare `MockNetwork` for request-shape and
invalid-input assertions. Migrate tests screen by screen using the reference
template's test as the model.

**Phase 6 — Harness and composition root.** Move remaining dependency
construction into the app entry point's `make*()` factories; add `--mock-*`
string launch arguments checked inline there (UI tests pass the literal
strings); wire previews with `@Previewable @State`. Previews, unit tests, and UI
tests now run the same code path production uses.

**Phase 7 — Replicate per screen.** Add each remaining screen as a feature
folder (model + view + presentation extensions), extracting shared UI into
`DesignSystem/` only when a pattern appears on two or more screens.

## Verification checklist

- The model can be constructed with `Model()` in both a view (`@State`) and a
  test with no container, factory, or DI framework.
- Every screen's load runs from `.task`/`.task(id:)`; no load in inits.
- Every protocol has a live implementation reachable through the environment
  default, and previews render without explicit wiring.
- Previews use `@Previewable @State`; no secondary view inits for injection.
- Mocks serve fixture bytes verbatim; the production decode path parses them.
- Tests assert request shapes with the recorded `TestableRequest` snapshots
  where relevant, and value snapshots for `@Model` state.
- UI tests drive mocks via launch arguments handled in the app entry point's
  `make*()` factories.
