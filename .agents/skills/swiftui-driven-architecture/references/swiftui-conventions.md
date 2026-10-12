# SwiftUI conventions and pitfalls

Each rule here exists because of a concrete failure mode, stated with it.

## Extract views as structs, never as computed `some View`

Do **not** break a view up with `private var header: some View { ... }`. That
property's value depends on the enclosing view's whole state, so SwiftUI
re-evaluates and re-renders it whenever the parent re-renders — defeating the
diffing structs get for free.

Make a real `View` struct taking only the data it needs as stored properties:

```swift
private struct DeparturesList: View {
    let departures: [CallAtLocation]
    let failure: String?
    var body: some View { ... }
}
```

Structs give SwiftUI stable identity and let it skip a subtree whose inputs
haven't changed. The only `some View` computed property in a `View` should be
its `body`; reserve other computed properties for plain values (`String`, `Int`,
`Bool`, model objects).

## Never create `State` manually

Do not call `State(initialValue:)` or write `_state` inside an `init`. Declare
the `@State` property with an inline default expression (optionally calling a
private `static` factory) and let SwiftUI own it. An `init` should configure only
**non**-`@State` stored properties.

```swift
struct MyModifier: ViewModifier {
    @State private var model = Self.makeModel()
    var onManualSearch: () -> Void

    init(onManualSearch: @escaping () -> Void = {}) {
        self.onManualSearch = onManualSearch  // never touch `model` here
    }

    private static func makeModel() -> Model { ... }
}
```

Manual `State` construction makes SwiftUI re-initialize the state on every view
update.

## Never launch a `Task` from a `static` factory

A `static func makeModel() -> Model` constructs and returns — nothing else. A
`Task { await model.load() }` fired from the factory escapes SwiftUI's
lifecycle, can run before the view is on screen, and (when the factory is also
used by a preview) leaves the load unowned. Trigger the initial load from the
owning view's `.task`.

## Previews inject with `@Previewable @State`, never a secondary init

Do **not** add `init(network:locationModel:favoritesModel:)` to a view just so a
preview can pass values in. The `@State` property's default expression still
*runs* in the preview process, so it falls back to `LiveNetwork()` and the
screen's `.task` fires a real request that fails (an empty-API-key call returns
an HTML error page → `DecodingError.dataCorrupted`, "Unexpected character '<'").

```swift
#Preview {
    @Previewable @State var network: NetworkProtocol = mockNetwork()
    @Previewable @State var locationModel = previewLocationAuthorization()
    @Previewable @State var modelContainer: ModelContainer = mockModelContainer()

    MainView()
        .environment(\.network, network)
        .environment(locationModel)
        .modelContainer(modelContainer)
}
```

Any view reading `@Environment(\.modelContext)` **must** get a
`.modelContainer(...)` in its preview — it traps at runtime otherwise.

## Two injection styles, and which is which

| Kind | How to publish | How to read |
| --- | --- | --- |
| Protocol seam (network, storage, location) | `@Entry var network: NetworkProtocol = LiveNetwork()` | `@Environment(\.network)` |
| `@Observable` model shared across screens | `.environment(favoritesModel)` | `@Environment(FavoritesModel.self)` |

Do **not** register an `@Observable` model as a custom `@Entry` and read
`@Environment(\.customKey)`. That adds an optional layer the view must unwrap
(`if let model { ... } else { ProgressView() }`) and is a step away from the
canonical `@Observable` injection. `@Environment(Model.self)` is non-optional and
fails loudly when the model is missing — correct for a required dependency.

The **view owns its model**: a screen-local model is `@State var model = X()`
inside that screen's view; a model shared by two screens is owned by the parent
(`MainView`) in `@State` and published into the environment.

## Debounced search: `.task(id:)`, not `.onChange` + `Task`

Bind `.searchable(text: $query)` to `@State` and load from
`.task(id: query) { await model.search(named: query, network: network) }`.
SwiftUI cancels the previous task when `id` changes, so a single in-model
debounce is enough:

```swift
try? await Task.sleep(for: .milliseconds(400))
guard !Task.isCancelled else { return }
// …request…
guard !Task.isCancelled else { return }
```

`.onChange(of: query) { Task { ... } }` spawns a new unstructured task per
keystroke that races the others and overwrites results out of order.

The `.task(id:)` form also re-runs the blank query on appear, which the model
uses to clear results and show the recents section.

## Cancellation guard on the loading flag

`.task(id:)` starts the replacement task **before** cancelling the old one, so a
cancelled load must not clobber the replacement's `isLoading = true`:

```swift
isLoading = true
defer {
    if !Task.isCancelled { isLoading = false }
}
```

Map transport cancellation to one type so models only handle `CancellationError`:

```swift
do { return try await URLSession.shared.data(for: request) }
catch URLError.cancelled { throw CancellationError() }
catch { throw error }
```

## Secrets as throwing computed properties

API keys come from a bundled, git-ignored `KEY=VALUE` env file, not from source.
Expose them as **throwing** computed properties (`Secrets.realtimeKey`) so a
missing or empty key throws when the request is built and surfaces through the
model's `failure` handling — instead of silently sending an empty key and
decoding an error page.

## SwiftData details

- The app entry point builds the `ModelContainer` once; views read
  `@Environment(\.modelContext)` and **hand the context into model methods**.
- One `@Model` aggregate root per feature with
  `@Relationship(deleteRule: .cascade)`; create it on demand on first write, and
  make `remove` a no-op when it's absent. Never `fatalError` on a missing
  aggregate.
- Sort in the model (display invariants), save from the caller (live app: SwiftData
  autosave; tests: explicit `context.save()`).
- **Never cache `container.mainContext`** — it is a computed property that vends
  the main-queue context. Binding `let context = container.mainContext` once and
  reusing it means inserts through one context don't appear in fetches through
  another, and persistence round-trip tests fail silently. Pass
  `container.mainContext` at each call site.

## Presentation lives on the domain type

Display logic (icons, labels, formatted dates/distances) goes in computed
properties on the value type, in a `Type+Feature.swift` extension next to its
first consumer. Call sites read `departure.lineLabel`, not
`StopDetailsModel.lineLabel(for: departure)` — the static "pass the value back
in" form hides the receiver and is what drifts when a second screen needs it.
Extra inputs (e.g. a `now` date) stay as method parameters on the extension.

## User-facing text is English

All in-app strings — `Text`, `Button` titles, labels — are English, even when the
API's data (stop names, etc.) is another language and is surfaced as-is.
`NSLocationWhenInUseUsageDescription` is the exception: it's the *system* prompt,
not in-app UI, so it may be localized.
