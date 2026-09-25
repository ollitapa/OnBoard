---
name: swiftui-driven-architecture
description: >-
  Build and refactor SwiftUI apps with an Apple-only, environment-injected architecture:
  @Observable screen models, @Entry protocol seams, @Environment(Model.self) shared
  models, SwiftData aggregate roots, and .task-driven async lifecycles. USE FOR: adding
  a SwiftUI screen, state management, dependency injection, previews, Swift Testing
  tests, mocks, or migrating off singletons, Combine MVVM, or TCA. DO NOT USE FOR:
  UIKit/AppKit, code that must keep Combine publishers, or general Swift questions.
argument-hint: 'Screen to add, or the dependency/seam to migrate'
---

# SwiftUI-Driven Architecture

The premise: **SwiftUI is the framework.** No Combine publishers, no coordinator
objects, no third-party state containers, no external dependencies. The entire
dependency surface is a few small protocols injected through the SwiftUI
environment, so the same views run in production, previews, unit tests, and UI
tests.

## When to use this architecture

- Greenfield SwiftUI app, or an existing app migrating away from
  singleton/global dependencies, `ObservableObject`/`@Published` MVVM, or a
  third-party state container.
- **Fit-check gate**: if the app's requests need cross-cutting concerns (auth,
  retry, caching, per-request analytics), invert the injection *from the start* —
  make the API client itself the injected protocol (`@Entry var api: any MyAPI`),
  with the transport a detail of its live implementation. Otherwise inject the
  transport. Do not retrofit this later.

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

Dependencies arrive as parameters on load/mutate methods
(`loadStops(network:latitude:longitude:)`), so a view writes
`@State var model = NearbyModel()` and a test writes `NearbyModel()` — no
container, no factory. Errors become `failure = String(describing: error)`;
only `CancellationError` is swallowed.

Template: [assets/screen-model.md](./assets/screen-model.md)

### 2. Protocol seams, published with `@Entry`, defaulting to live

```swift
extension EnvironmentValues {
    @Entry var network: NetworkProtocol = LiveNetwork()
}
```

**Rule of need**: if you can't name a second implementation you'd actually want
(mock, preview stub, cache-decorated), you don't need the protocol yet. The
`@Entry` default is live, so views and previews render with zero wiring. The app
entry point is the **composition root** — the only place deciding which
implementations exist.

Shared `@Observable` models are injected differently — see rule 8.

### 3. Load in `.task`/`.task(id:)`, never in init or a factory

```swift
.task(id: location.coordinate) {
    guard let coordinate = location.coordinate else { return }
    await model.loadStops(network: network, latitude: coordinate.latitude, ...)
}
```

SwiftUI owns the async lifetime and cancels on `id` change. The loading flag
needs a cancellation guard, because `.task(id:)` starts the replacement task
*before* cancelling the old one:

```swift
isLoading = true
defer {
    if !Task.isCancelled { isLoading = false }
}
```

Template: [assets/screen-view.md](./assets/screen-view.md). Debounced search,
cancellation mapping, and preview wiring:
[references/swiftui-conventions.md](./references/swiftui-conventions.md)

### 4. SwiftData as an injected dependency, one aggregate root per feature

The app entry point builds the `ModelContainer` once; views read
`@Environment(\.modelContext)` and **hand the context into model methods**
(`toggle(_:name:lines:context:)`), so the model stays storage-agnostic. Persist
each feature's collection as one `@Model` aggregate with a cascading
relationship, created on demand on first write. Container-open failure policy
(fail fast vs. rebuild) is a written-down product decision.

### 5. Presentation on the domain type

Display logic lives in computed properties on the value types via
`Type+Feature.swift` extensions next to their consumers — shared across screens
instead of duplicated per view, and never as `static func foo(for: SomeType)`.

### 6. Feature folders over type folders

A screen's model, view, and presentation extensions live together; adding a
feature is adding a folder. Only cross-cutting infrastructure (`Network/`,
`Location/`, `Api/`) and shared UI (`DesignSystem/`) sit outside.

### 7. Design system extraction rule

Shared components live in `DesignSystem/`, one per file, each with a `#Preview`.
View structs stay feature-local until the pattern appears on **two or more**
screens — then extract. Prefer extending an existing component over adding a
near-duplicate. Design tokens are asset-catalog colorsets with generated symbols
(`.ink`, `.panel`, …); no hand-written `Color` extensions.

## Hard rules

Each is backed by a real failure mode, stated in the reference files.

1. **No `ObservableObject`/`@Published`** — `@Observable` re-renders a screen
   only for the properties its body reads.
2. **Never load in a model's `init`, a view's `init`, or a `static` factory** —
   a `Task` fired there escapes SwiftUI's lifecycle and runs before the view is
   on screen.
3. **Never create `State` manually** (`State(initialValue:)`, writing `_state`) —
   declare `@State` with an inline default; inits configure only non-`@State`
   properties.
4. **Never add a secondary view init just for preview injection** — the `@State`
   default expression still runs and fires real, failing requests. Use
   `@Previewable @State` plus `.environment(...)`/`.modelContainer(...)`.
5. **Never `.onChange(of:) { Task { ... } }` for debounced search** —
   unstructured tasks race and overwrite results out of order. Use
   `.task(id: query)`.
6. **Never split a view with `private var x: some View`** — extract a real
   `View` struct taking only the data it needs, or SwiftUI re-renders the
   subtree on every parent update.
7. **No singletons or global containers** — the environment is the composition
   root's delivery mechanism.
8. **`@Entry` is for protocol seams only** — publish a shared `@Observable`
   model with `.environment(model)` and read `@Environment(Model.self)`, which
   is non-optional and fails loudly. A custom `@Entry` for a model forces every
   view to unwrap an optional.
9. **Never hand-build API model values in a mock** — wire-shape JSON only.
10. **Never compare `@Model` instances with `==` for field equality** — the
    macro's `==` is object identity. Compare `Equatable` value snapshots (not
    tuples).
11. **A view reading `@Environment(\.modelContext)` must get a
    `.modelContainer(...)` in previews** — it traps otherwise.
12. **Never cache `container.mainContext`** — it's computed; pass it at each
    call site or mutations vanish between contexts.
13. **Secrets are throwing computed properties** over a bundled, git-ignored env
    file, so a missing key surfaces through `failure` instead of sending an empty
    key.
14. **User-facing in-app text stays English** even when API data is another
    language (system permission prompts may localize).

## Procedures

### Adding a screen

1. Create `<Feature>/` with a model, a view, and any presentation extensions.
2. Copy [assets/screen-model.md](./assets/screen-model.md) — empty `init()`,
   `failure`/`isLoading`/rows, cancellation-guarded `defer`.
3. Copy [assets/screen-view.md](./assets/screen-view.md) — environment
   dependencies, `@State` model, `.task(id:)` load, sub-views as structs,
   `@Previewable @State` preview.
4. Add a `@MainActor` Swift Testing suite constructing `Model()` and injecting a
   fixture-based mock: [assets/mock-service.md](./assets/mock-service.md).
5. Run the verification below.

### Migrating an existing app

Seven phases, each leaving the app working:
[references/migration.md](./references/migration.md).

## Verification

Run the anti-pattern scan, then the test suite:

```sh
./.agents/skills/swiftui-driven-architecture/scripts/check-architecture.sh OnBoard
xcodebuild test -scheme OnBoard -destination 'platform=iOS Simulator,name=iPhone 16'
```

Then confirm by review:

- The model constructs as `Model()` in both a view (`@State`) and a test, with no
  container, factory, or DI framework.
- Every load runs from `.task`/`.task(id:)`.
- Every protocol has a live implementation reachable through the environment
  default, so previews render without explicit wiring.
- Previews use `@Previewable @State`; no secondary view inits for injection.
- Mocks serve fixture bytes verbatim and the production decode path parses them.
- UI tests drive mocks via launch arguments handled in the app entry point's
  `make*()` factories.

## Reference

- [references/swiftui-conventions.md](./references/swiftui-conventions.md) —
  view/preview/state/SwiftData pitfalls with their failure modes
- [references/mocks-and-tests.md](./references/mocks-and-tests.md) — the
  wire-shape fixture doctrine and test conventions
- [references/migration.md](./references/migration.md) — phased adoption

A working implementation of every pattern above lives in the OnBoard repo
(`README.md`, `CONTRIBUTING.md`, and the feature folders under `OnBoard/`); cite
those files only when working inside that repo.
