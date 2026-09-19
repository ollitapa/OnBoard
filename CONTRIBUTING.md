# Contributing to OnBoard

## Development Guidelines

### Testing

- **Prefer `== []` over `isEmpty`** for array comparisons in tests. This provides better error debugging as the test framework can show the actual vs expected values.

- **Use Equatable conformance** for model types to enable full object comparison in tests rather than comparing individual properties. Rely on the **synthesized** (memberwise) `Equatable`/`Hashable` conformance — almost never write a custom `==` or `hash(into:)`. If you need exclusivity or lookup based on only an `id`, don't express that by overriding `==` to compare `id` alone (which makes equality inconsistent with hashing and the whole value); instead model the collection as a `Dictionary<id, value>` keyed by that id, or find entries with a predicate (`favorites.firstIndex { $0.id == stopId }`). Keep the type's identity (`Identifiable`'s `id`) and its value equality as separate concerns. **Exception: SwiftData `@Model` classes** — the `@Model` macro synthesizes `Equatable`/`Hashable` as **object identity**, not memberwise, so two equal-by-field models are not `==`. For `@Model` types, compare a value snapshot (e.g. a `(id, name, lines)` tuple) in `#expect`, not the model object.

- **Mock dependencies** using the dependency injection pattern. The project injects `NetworkProtocol` and `@Observable` models through the SwiftUI environment (see Network Layer and Observable Models).

- **Prefer feature-specific service mocks over a bare `MockNetwork`**: `MockTrafiklabService` (and the older `MockNearbyServer`) serve canned responses for the real endpoint paths the app calls, so a model's full production decode path is exercised. Configure `MockTrafiklabService` with multiline JSON fixtures in the endpoint's wire shape (`nearbyStops`, `departuresByAreaId`, `tripsByKey`, `stopGroups`), not hand-built API model values — a fixture should read like a captured API response, and it is pushed through as raw JSON bytes (never converted into the API's Swift models; only the search filter and the per-key lookups touch generic `JSONSerialization` values). Timestamps inside a fixture may use relative markers (`"now"`, `"now+2"`, `"now-10"`, in minutes) resolved at creation so previews and UI tests always show fresh times; malformed fixture JSON traps with the fixture named. Reach for the bare `MockNetwork` (handler registration) only when a test needs to assert on a specific request shape or feed invalid JSON (`loadStopsInvalidJSON`, `loadDeparturesInvalidJSON`). A preview that wires a `MockNetwork()` with **no handlers** into a screen whose `.task` loads data will surface `NoResponseConfigured` as a failure string, not a working preview — use `MockTrafiklabService` (or `mockNetwork()`) for previews that need data.

- **Preview/test helper functions live in the app target**: `mockNetwork()`, `previewLocationAuthorization()`, `mockModelContainer()`, and `emptyModelContainer()` are top-level functions in the app target (not the test target) because previews and the UI-test launch-argument harness both call them. The harness is driven by string launch arguments (`--mock-network`, `--skip-location-permission`, `--mock-storage`) checked inline in `MyApp.make*()` — these are **not** shared `let` constants (they were inlined so the app entry point is self-contained), so UI tests pass the literal strings. Add a new helper alongside its dependency when a preview needs pre-configured state, and a matching `--mock-*` branch in `MyApp` if a UI test needs it.

- **Test helpers**: Use the static helper methods on `MockNetwork` for creating test responses:
  - `MockNetwork.makeResponse(json:statusCode:)` - for raw JSON strings
  - `MockNetwork.makeJSONResponse(_:statusCode:)` - for Encodable values

### Network Layer

- **Protocol-oriented**: All network operations should conform to `NetworkProtocol`
- **API keys come from a bundled env file, not source**: `Trafiklab` reads its keys through `Secrets`, which parses the `KEY=VALUE` env file bundled with the app: the git-ignored `OnBoard/Secrets.env` (see the README's "API keys" section). The file-system-synchronized target bundles the file as a resource automatically. The key accessors (`Secrets.realtimeKey`/`resrobotKey`) are throwing computed properties: a missing or empty key throws `SecretMissingForKey(key:)` when a request is built, so it surfaces through the view model's `failure` handling instead of silently sending an empty key.
- **Dependency injection**: Inject `NetworkProtocol` through the SwiftUI environment: read it with `@Environment(\.network)` at the call site and publish it with `.environment(\.network, network)`. The environment default is `LiveNetwork`, so views render in previews/tests without an explicit value; previews/tests override it.
- **Live implementation**: `LiveNetwork` uses `URLSession.shared` for production
- **Mock implementation**: `MockNetwork` provides handler registration and request tracking for testing

### Storage Layer

The app persists state with SwiftData (`@Model` classes plus a `ModelContainer`/`ModelContext`), the storage analogue of the network layer: the `ModelContainer` is built once by the app entry point (`MyApp`) and injected into the SwiftUI environment with `.modelContainer(container)`; views read the context with `@Environment(\.modelContext)` and hand it to their model's load/mutate methods. The custom `AsyncStorage` framework that preceded it has been removed.

- **Storage is a dependency, not a global**: The `@MainActor @Observable` view model is storage-agnostic: it takes no store in `init` and receives the `ModelContext` as a parameter on each load/mutate method (`loadFavorites(context:)`, `toggle(_:name:lines:context:)`), so it depends only on the SwiftData store injected into the environment. The app entry point owns and builds the `ModelContainer`; previews/tests inject an in-memory container. Do not reach for a singleton context or a global container inside a model.
- **One aggregate root per feature**: Persist a feature's collection as a single `@Model` aggregate (e.g. `StoredFavorites` holds the `[Favorite]` relationship with `@Relationship(deleteRule: .cascade)`), not as many independent rows the model must round-trip. `FavoritesModel.loadFavorites` fetches the one `StoredFavorites` and the view mutates its `favorites` array; deleting the aggregate cascades to all its favourites. A `@Model` can itself own `@Model` relationships — use that instead of encoding nested value blobs.
- **`@Model` gives identity, not value equality**: The `@Model` macro synthesizes `Identifiable`, `Hashable`, `Observable`, and `PersistentModel`, and SwiftData's default `Hashable`/`Equatable` is **object identity**, not memberwise comparison. So never compare two `@Model` instances with `==` to check their fields (two equal-by-field favourites are not `==`). In tests, compare a value snapshot — a small `Equatable` struct standing in for the fields (e.g. `FavoriteSnapshot { id, name, lines }`), **not** a `(id, name, lines)` tuple, since Swift tuples don't conform to `Equatable` and `[Tuple].== [Tuple]` won't compile. This is why the repo's "synthesized `Equatable`" convention (see Testing) applies to plain value types, not to `@Model` classes.
- **The model creates the aggregate on demand**: If a feature's aggregate may not exist yet (first launch), the mutate method inserts one on the first write rather than requiring the caller to seed it. `FavoritesModel.toggle` creates and inserts a `StoredFavorites` when none is loaded; `remove` is a no-op when the aggregate is `nil`. Don't `fatalError` on a missing aggregate.
- **Sort in the model, persist from the caller**: Keep display invariants (e.g. favourites sorted by name) in the model — `toggle` re-sorts after each add so the view never sees unsorted data. The model mutates the context but does not own the save lifecycle; the caller saves the `ModelContext` when it wants the change to outlive the run. (The live app relies on SwiftData autosave; tests call `context.save()` explicitly.)
- **`container.mainContext` returns a fresh context each access — don't cache it**: `ModelContainer.mainContext` is a computed property that vends the main-queue context, and reaching it returns a context tied to the container's current state. Capturing `let context = container.mainContext` once and reusing that *stored* reference across calls means the model and any later access can end up with different context instances, so inserts/mutations made through one don't show up in fetches through another — favourites a model just `toggle`d appear empty to a reader, and persistence round-trip tests fail silently. Pass `container.mainContext` **at each call site** (`model.toggle(..., context: container.mainContext)`) rather than binding a `let context` once, and have tests return the `ModelContainer` (not a captured `ModelContext`) from their helper. In the live app, `@Environment(\.modelContext)` already gives the view a single shared context per environment, so this caveat is mainly for tests and any code that holds a `ModelContainer` directly.

### Observable Models

App state is held in `@MainActor @Observable final class` models (`NearbyModel`, `StopDetailsModel`, `FavoritesModel`), each owning one screen's load lifecycle and surfacing transport/storage errors as a `failure: String?` rather than throwing.

- **The view owns its model**: The top-level view (`MainView`) owns a shared model in `@State` (e.g. `@State var favoritesModel = FavoritesModel()`) and publishes it into the environment so every screen that mutates the same state reads one instance. A model is never a singleton or a global; whoever needs to share it constructs it once and injects it.
- **One model per screen for screen-local state**: A screen's model is constructed with `@State var model = SomeModel()` inside that screen's view and built from the environment's injected dependencies (network, `ModelContext`) at load time. The model's `init` takes no dependencies; load/mutate methods receive them (`loadStops(network:latitude:longitude:)`, `loadDepartures(network:areaId:)`, `loadFavorites(context:)`) so tests inject a mock/context directly. A *shared* model (e.g. favourites, used by two screens) is owned by the parent and read from `@Environment(Model.self)` instead.
- **Inject `@Observable` models via `@Environment(Model.self)`**: Publish an `@Observable` model with `.environment(model)` and read it with `@Environment(Model.self)`. Do not register it as a custom `@Entry` on `EnvironmentValues` and read `@Environment(\.customKey)` — that adds an optional layer the view then has to unwrap (`if let model { ... } else { ProgressView() }`), and it's a step away from the canonical `@Observable` injection. `@Environment(Model.self)` is non-optional and fails loudly if the model is missing, which is what you want for a required dependency.
- **Don't launch a `Task` from a `static` model factory**: A `static func makeModel() -> Model` should construct and return the model only. Trigger the initial load from the owning view's `.task { await model.load() }` modifier, which SwiftUI ties to the view's lifetime and re-runs on the right actor. A `Task { await model.load() }` fired from the factory escapes SwiftUI's lifecycle, can run before the view is on screen, and (when the factory is also used by a preview) leaves the load unowned.

### Code Style

- **Use documentation comments**: Add Swift documentation comments (`///`) for public APIs and complex logic
- **Follow existing patterns**: Match the repository's existing style and architecture
- **Small changes**: Make the smallest correct change that solves the problem
- **Prefer computed properties and extensions over static helper functions**: When a piece of logic answers a question *about a value* (e.g. a model's display label, delay minutes, or parsed date), model it as a computed property on that type, ideally in a `Type+Feature.swift` extension next to its consumer — never as a `static func foo(for: SomeType)` on an unrelated type. Call sites should read `departure.lineLabel`, not `StopDetailsModel.lineLabel(for: departure)`. The static "pass the value back in" form is a Java-style smell and hides the receiver. Reserve static functions for true factories (`init`s) or stateless utilities that don't have a natural receiver. When logic needs extra inputs beyond the receiver (e.g. a `now` date), keep those as method parameters on the extension rather than reaching into a model.

- **Put presentation logic on the domain type, not duplicated across screens**: When a value maps to UI in more than one screen (e.g. a Trafiklab transport mode rendered both as the Stop board's mode blip and the Search row's icon), model it once as a computed property on that domain type. `TransportMode` is a `Codable Equatable Hashable` value wrapping `rawMode`; its `icon` (the SF Symbol for `BUS`/`METRO`/`TRAM`/`TRAIN`/`BOAT`/`TAXI`) lives in an `extension TransportMode`, so `ModeBlip` reads `mode.icon` and `StopGroup.modeIcons` reads `$0.icon`. Resist copying the `switch` into a per-screen `enum`/`static func` (a duplicated `SearchTransport.icon(for:)` beside `ModeBlip.modeIcon(for:)`); the second copy is what drifts. Keep the *value* (and its `Hashable`/`Codable` shape) in `Api/`, and the *presentation* extension next to whichever consumer owns the first call site.

### SwiftUI Conventions

These conventions keep view code consistent and avoid SwiftUI initialization pitfalls.

- **Extract views as structs, not computed `some View` properties**: Do not break a view into smaller pieces with `private var something: some View { ... }`. Each computed property returns an opaque, type-erased-to-the-caller view whose value depends on the enclosing view's whole state, so SwiftUI re-evaluates and re-renders it whenever the parent re-renders — defeating the diffing that structs get for free. Instead, make an actual `View` struct that takes only the data it needs as stored properties (e.g. `private struct DeparturesList: View { let departures: [CallAtLocation] ... }`). Structs give SwiftUI a stable identity and let it skip re-rendering a subtree whose inputs haven't changed. Reserve computed properties for non-view values (plain `String`, `Int`, `Bool`, model objects); the only `some View` computed property in a `View` should be its `body`.
- **Indentation**: 4 spaces. When a call or initializer doesn't fit on one line, put the opening delimiter on the first line and wrap each argument on its own line, indented 4 spaces from the start of the statement; place the closing delimiter on its own line aligned with the start of the statement. Apply the same wrapping to nested calls, array literals, and closures. For example:
  ```swift
  locationDelegate?.locationManager(
      self,
      didUpdateLocations: [
          CLLocation(
              coordinate: coordinate,
              altitude: 0,
              horizontalAccuracy: 5,
              verticalAccuracy: 5,
              timestamp: Date()
          )
      ]
  )
  ```
  For an `init` whose parameters don't fit, wrap the same way:
  ```swift
  init(
      authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse,
      coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 59.31, longitude: 18.07)
  ) {
      ...
  }
  ```

- **Never create `State` manually**: Do not call `State(initialValue:)` or write to `_state` inside an `init`. Declare the `@State` property with its default value as an inline initializer (e.g. `@State private var model = Self.makeModel()`) and let SwiftUI own it. A type's `init` should only configure its *non*-`@State` stored properties; the `@State` value comes from its default expression, which may call a private `static` factory. This avoids SwiftUI re-initializing the state on each view update and keeps the init simple:
  ```swift
  struct MyModifier: ViewModifier {
      @State private var model: Model = Self.makeModel()
      var onManualSearch: () -> Void

      init(onManualSearch: @escaping () -> Void = {}) {
          // Only configure non-@State properties here; never touch `model`.
          self.onManualSearch = onManualSearch
      }

      private static func makeModel() -> Model { ... }
  }
  ```
  If a secondary init needs to supply a different model (e.g. for previews/tests), assign it to the `@State` property directly in that init rather than constructing `State`.

  The app entry point (`MyApp`), not the root view, owns the shared dependencies as `@State` (`network`, `locationModel`, `modelContainer`) and injects them into the environment on the root view. The root view (`MainView`) therefore has an empty `init()` and reads every dependency from the environment (`@Environment(\.network)`, `@Environment(LocationAuthorization.self)`, `@Environment(\.modelContext)`, `@Environment(FavoritesModel.self)`). This keeps the production wiring in one place and lets `MainView` be constructed with no arguments in previews.

- **Use `@Previewable @State` to inject dependencies into previews**: A preview that needs to supply environment dependencies (network, location model, `ModelContainer`, an `@Observable` model) declares them with `@Previewable @State var x = …` at the top of the `#Preview` block, then publishes them onto the view with `.environment(\.network, x)`, `.environment(x)`, `.modelContainer(x)`. **Do not** instead give the view a secondary `init(network:locationModel:favoritesModel:)` just so the preview can pass values through `@State` — that default `@State` initializer expression (`Self.makeNetwork()`) still *runs* in the preview process, and when it falls back to `LiveNetwork()` (no `--mock-network` launch arg in previews) the screen's `.task` fires a real request that fails (e.g. an empty-API-key ResRobot call returns an HTML error page → `DecodingError.dataCorrupted` / "Unexpected character '<'"). `@Previewable @State` makes the preview the source of truth and lets the view stay construction-free:
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
  This is also why a preview that needs a `@Environment(\.modelContext)` (any view with `@Environment(\.modelContext)`) **must** get a `.modelContainer(...)` — a `@Model`-reading view traps at runtime if no container is in the environment.

- **User-facing text is English**: All in-app strings — view `Text`, `Button` titles, labels — are in English. The Trafiklab API is Swedish and its data (stop names, etc.) is surfaced as-is, but the app's own UI chrome stays English. The `NSLocationWhenInUseUsageDescription` Info.plist value is an exception: it is the *system* permission prompt, not in-app UI, so it may be localized to match the OS sheet.

- **Drive `.searchable` queries with `.task(id:)`, not `.onChange` + `Task`**: For a live (search-as-you-type) screen, bind the `.searchable(text: $query, ...)` field to `@State` and run the load from `.task(id: query) { await model.search(named: query, ...) }`. SwiftUI cancels the previous task when `id` changes, so a single in-model debounce — `try? await Task.sleep(for: .milliseconds(400))` followed by `guard !Task.isCancelled else { return }` before and after the request — yields a correct debounce without unstructured `Task`s or manual cancellation bookkeeping. A `.onChange(of: query) { Task { ... } }` instead spawns a *new* task per keystroke that races the old ones and overwrites results out of order; never use it for debounced search. The `.task(id:)` form also re-runs the initial (blank) query on appear, which the model uses to clear results and show the recents section.

## Project Structure

```
OnBoard/
├── Network/              # Network layer (NetworkProtocol + live/mock + CombinedNetwork)
│   ├── NetworkProtocol.swift
│   ├── NetworkDependency.swift
│   ├── LiveNetwork.swift
│   ├── MockNetwork.swift
│   └── MockNearbyServer.swift  # mockNetwork(), previewLocationAuthorization()
├── Api/                  # Trafiklab API client, response models, MockTrafiklabService
├── Location/             # Location permission flow and managers
├── Nearby/               # Nearby stops feature
│   ├── NearbyModel.swift
│   └── NearbyView.swift
├── Favorites/            # Favorite stops feature (SwiftData @Model Favorite/StoredFavorites, FavoritesModel, FavoritesView, mock/empty containers)
├── Search/               # Search feature
└── StopDetails/          # Stop board feature (model, view, CallAtLocation presentation/favorites helpers)

OnBoardTests/
├── NearbyModelTests.swift
├── StopDetailsModelTests.swift
├── FavoritesModelTests.swift
├── CombinedNetworkTests.swift
├── CallAtLocationFavoritesTests.swift
└── LocationAuthorizationTests.swift
```

## Testing Example

```swift
import Testing
@testable import OnBoard

struct MyModelTests {
    @Test func testSuccess() async throws {
        // Given
        var mockNetwork = MockNetwork()
        let expectedURL = URL(string: "https://api.example.com/endpoint")!
        let expectedRequest = MockNetwork.TestableRequest(
            url: expectedURL,
            httpMethod: "GET",
            httpBody: nil
        )
        
        mockNetwork.registerHandler { request in
            if request.url == expectedURL {
                return MockNetwork.makeJSONResponse(MyModel.Response(data: "test"))
            }
            return nil
        }
        
        let model = MyModel()

        // When
        await model.loadData(network: mockNetwork)

        // Then
        #expect(model.items == [])
        #expect(mockNetwork.testableRequests[0] == expectedRequest)
    }
}
```
