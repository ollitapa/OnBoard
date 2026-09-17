# Contributing to OnBoard

## Development Guidelines

### Testing

- **Prefer `== []` over `isEmpty`** for array comparisons in tests. This provides better error debugging as the test framework can show the actual vs expected values.

- **Use Equatable conformance** for model types to enable full object comparison in tests rather than comparing individual properties. Rely on the **synthesized** (memberwise) `Equatable`/`Hashable` conformance — almost never write a custom `==` or `hash(into:)`. If you need exclusivity or lookup based on only an `id`, don't express that by overriding `==` to compare `id` alone (which makes equality inconsistent with hashing and the whole value); instead model the collection as a `Dictionary<id, value>` keyed by that id, or find entries with a predicate (`favorites.firstIndex { $0.id == stopId }`). Keep the type's identity (`Identifiable`'s `id`) and its value equality as separate concerns.

- **Mock dependencies** using the dependency injection pattern. The project injects `NetworkProtocol` and `@Observable` models through the SwiftUI environment (see Network Layer and Observable Models).

- **Prefer feature-specific service mocks over a bare `MockNetwork`**: `MockTrafiklabService` (and the older `MockNearbyServer`) serve canned, `Codable`-round-trippable responses for the real endpoint paths the app calls, so a model's full encode→decode path is exercised. Reach for the bare `MockNetwork` (handler registration) only when a test needs to assert on a specific request shape or feed invalid JSON (`loadStopsInvalidJSON`, `loadDeparturesInvalidJSON`). A preview that wires a `MockNetwork()` with **no handlers** into a screen whose `.task` loads data will surface `NoResponseConfigured` as a failure string, not a working preview — use `MockTrafiklabService` (or `mockNetwork()`) for previews that need data.

- **Preview/test helper functions live in the app target**: `mockNetwork()`, `previewLocationAuthorization()`, and `mockFavoritesModel()` are top-level functions in the app target (not the test target) because previews and the `--mock-network`/`--skip-location-permission` launch-argument harness both call them. Add a new one alongside its dependency when a preview needs pre-configured state.

- **Test helpers**: Use the static helper methods on `MockNetwork` for creating test responses:
  - `MockNetwork.makeResponse(json:statusCode:)` - for raw JSON strings
  - `MockNetwork.makeJSONResponse(_:statusCode:)` - for Encodable values

### Network Layer

- **Protocol-oriented**: All network operations should conform to `NetworkProtocol`
- **Dependency injection**: Inject `NetworkProtocol` through the SwiftUI environment: read it with `@Environment(\.network)` at the call site and publish it with `.environment(\.network, network)`. The environment default is `LiveNetwork`, so views render in previews/tests without an explicit value; previews/tests override it.
- **Live implementation**: `LiveNetwork` uses `URLSession.shared` for production
- **Mock implementation**: `MockNetwork` provides handler registration and request tracking for testing

### Storage Layer

The app persists state through the `AsyncStorage<Value, Id>` protocol (`OnBoard/Storage/`), the storage analogue of `NetworkProtocol`: a single `value(for:)` / `saveValue(_:for:)` interface with `MemoryStorage`, `FileStorage`, `CombinedStorage`, and `CodableStorage` conformers. Follow the same conventions as the network layer.

- **Storage is a dependency, not a global**: A model that persists state takes a raw `AsyncStorage<Data, String>` (the `FileStorage`-shaped primitive) in its `init` and does its own JSON encode/decode of the value it stores via `.codable(for:)`, depending only on the same storage primitive the rest of the app uses. The model's `init` stays otherwise empty; the view that *owns* the model builds the store (e.g. `liveFavoritesStorage()` = file-backed store `.combined(with:)` an in-memory cache) and passes it in. Do not hand the model a pre-decoded value type or a domain-specific storage typealias — that couples the storage layer to one feature.
- **Wrap a file store with a memory cache**: Build a live store as `MemoryStorage<Value, Id>().combined(with: FileStorage(...))` (or `.codable(for:)` on top) so repeated reads don't hit disk. `combined(with:)` reads the cache first and back-fills/promotes from the backing store; writes push to both and roll the backing store back on a cache write failure.
- **Make `AsyncStorage` conformers `Sendable`**: The protocol is `Sendable` (mirroring `NetworkProtocol`), so a `@MainActor` model can hold `any AsyncStorage<...>` and `await` its methods under Swift 6 without a region-isolation data-race warning. Value-type conformers (`MemoryStorage`, `FileStorage`, `CombinedStorage`, `CodableStorage`) get `Sendable` for free; new conformers must be `Sendable` too.
- **Tests/previews pass an in-memory store**: `MemoryStorage<Data, String>()` satisfies `some AsyncStorage<Data, String>` and is synchronous, so preview/test setup can `storage.saveValue(..., for: id)` inline (no `Task`) before constructing the model.
- **Roll back on a write failure**: When a persist call can fail, capture the prior in-memory state, mutate, attempt the write, and on failure restore the prior state and surface the error in a `failure: String?` rather than leaving the view and the store out of sync. Use a `FailAfterFirstSaveStorage`-style helper (first save succeeds, later saves throw) to exercise this path; a store that throws on *every* save also rolls back the very first change, so it can't test the rollback-after-success case.

### Observable Models

App state is held in `@MainActor @Observable final class` models (`NearbyModel`, `StopDetailsModel`, `FavoritesModel`), each owning one screen's load lifecycle and surfacing transport/storage errors as a `failure: String?` rather than throwing.

- **The view owns its model**: The top-level view (`MainView`) owns a shared model in `@State` (built by a private `static` factory) and publishes it into the environment so every screen that mutates the same state reads one instance. A model is never a singleton or a global; whoever needs to share it constructs it once and injects it.
- **One model per screen for screen-local state**: A screen's model is constructed with `@State var model = SomeModel()` inside that screen's view and built from the environment's injected dependencies (network, storage) at load time. The model's `init` takes no dependencies; load methods receive them (`loadStops(network:latitude:longitude:)`, `loadDepartures(network:areaId:)`) so tests inject a mock directly. A *shared* model (e.g. favourites, used by two screens) is owned by the parent and read from `@Environment(Model.self)` instead.
- **Inject `@Observable` models via `@Environment(Model.self)`**: Publish an `@Observable` model with `.environment(model)` and read it with `@Environment(Model.self)`. Do not register it as a custom `@Entry` on `EnvironmentValues` and read `@Environment(\.customKey)` — that adds an optional layer the view then has to unwrap (`if let model { ... } else { ProgressView() }`), and it's a step away from the canonical `@Observable` injection. `@Environment(Model.self)` is non-optional and fails loudly if the model is missing, which is what you want for a required dependency.
- **Don't launch a `Task` from a `static` model factory**: A `static func makeModel() -> Model` should construct and return the model only. Trigger the initial load from the owning view's `.task { await model.load() }` modifier, which SwiftUI ties to the view's lifetime and re-runs on the right actor. A `Task { await model.load() }` fired from the factory escapes SwiftUI's lifecycle, can run before the view is on screen, and (when the factory is also used by a preview) leaves the load unowned.

### Code Style

- **Use documentation comments**: Add Swift documentation comments (`///`) for public APIs and complex logic
- **Follow existing patterns**: Match the repository's existing style and architecture
- **Small changes**: Make the smallest correct change that solves the problem
- **Prefer computed properties and extensions over static helper functions**: When a piece of logic answers a question *about a value* (e.g. a model's display label, delay minutes, or parsed date), model it as a computed property on that type, ideally in a `Type+Feature.swift` extension next to its consumer — never as a `static func foo(for: SomeType)` on an unrelated type. Call sites should read `departure.lineLabel`, not `StopDetailsModel.lineLabel(for: departure)`. The static "pass the value back in" form is a Java-style smell and hides the receiver. Reserve static functions for true factories (`init`s) or stateless utilities that don't have a natural receiver. When logic needs extra inputs beyond the receiver (e.g. a `now` date), keep those as method parameters on the extension rather than reaching into a model.

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

  For a top-level view that owns several shared dependencies as `@State` (e.g. `MainView`'s `network`, `locationModel`, `favoritesModel`), give each one a default inline initializer driven by launch arguments (the `--mock-network` / `--skip-location-permission` UI-test harness), keep `init()` empty, and add one secondary `init` that previews/tests use to override **all** the `@State` dependencies at once. Don't split this into multiple secondary inits that each override a subset and leave the rest at the default — that produces combinations (e.g. a real `LiveNetwork` paired with a pre-authorized location model) that are nonsensical for a preview and force the view to handle `nil`/mismatched state. One explicit-everything init keeps the production path and the preview/test path clearly separated:
  ```swift
  struct MainView: View {
      @State var network: any NetworkProtocol = Self.makeNetwork()
      @State var locationModel: LocationAuthorization = Self.makeLocationAuthorization()
      @State var favoritesModel: FavoritesModel = Self.makeFavoritesModel()

      init() { }

      init(
          network: any NetworkProtocol,
          locationModel: LocationAuthorization,
          favoritesModel: FavoritesModel
      ) {
          self.network = network
          self.locationModel = locationModel
          self.favoritesModel = favoritesModel
      }
  }
  ```

- **User-facing text is English**: All in-app strings — view `Text`, `Button` titles, labels — are in English. The Trafiklab API is Swedish and its data (stop names, etc.) is surfaced as-is, but the app's own UI chrome stays English. The `NSLocationWhenInUseUsageDescription` Info.plist value is an exception: it is the *system* permission prompt, not in-app UI, so it may be localized to match the OS sheet.

## Project Structure

```
OnBoard/
├── Network/              # Network layer (NetworkProtocol + live/mock + CombinedNetwork)
│   ├── NetworkProtocol.swift
│   ├── NetworkDependency.swift
│   ├── LiveNetwork.swift
│   ├── MockNetwork.swift
│   └── MockNearbyServer.swift  # mockNetwork(), previewLocationAuthorization(), mockFavoritesModel()
├── Storage/              # AsyncStorage layer (Memory/File/Combined/Codable)
├── Api/                  # Trafiklab API client, response models, MockTrafiklabService
├── Location/             # Location permission flow and managers
├── Nearby/               # Nearby stops feature
│   ├── NearbyModel.swift
│   └── NearbyView.swift
├── Favorites/            # Favorite stops feature (Favorite, FavoritesModel, FavoritesView, live store)
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
