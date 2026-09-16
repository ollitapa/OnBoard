# Contributing to OnBoard

## Development Guidelines

### Testing

- **Prefer `== []` over `isEmpty`** for array comparisons in tests. This provides better error debugging as the test framework can show the actual vs expected values.

- **Use Equatable conformance** for model types to enable full object comparison in tests rather than comparing individual properties.

- **Mock dependencies** using the dependency injection pattern. The project uses environment values for dependencies like `NetworkProtocol`.

- **Test helpers**: Use the static helper methods on `MockNetwork` for creating test responses:
  - `MockNetwork.makeResponse(data:response:)` - for raw data
  - `MockNetwork.makeResponse(json:statusCode:)` - for JSON dictionaries
  - `MockNetwork.makeJSONResponse(_:statusCode:)` - for Encodable values

### Network Layer

- **Protocol-oriented**: All network operations should conform to `NetworkProtocol`
- **Dependency injection**: Use `@Environment(\.network)` to access network functionality
- **Live implementation**: `LiveNetwork` uses `URLSession.shared` for production
- **Mock implementation**: `MockNetwork` provides handler registration and request tracking for testing

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

- **User-facing text is English**: All in-app strings — view `Text`, `Button` titles, labels — are in English. The Trafiklab API is Swedish and its data (stop names, etc.) is surfaced as-is, but the app's own UI chrome stays English. The `NSLocationWhenInUseUsageDescription` Info.plist value is an exception: it is the *system* permission prompt, not in-app UI, so it may be localized to match the OS sheet.

## Project Structure

```
OnBoard/
├── Network/              # Network layer
│   ├── NetworkProtocol.swift
│   ├── NetworkDependency.swift
│   ├── LiveNetwork.swift
│   └── MockNetwork.swift
├── Api/                  # Trafiklab API client and response models
├── Location/             # Location permission flow and managers
├── Nearby/               # Nearby stops feature
│   ├── NearbyModel.swift
│   └── NearbyView.swift
├── Favorites/            # Favorite stops feature
├── Search/               # Search feature
└── StopDetails/          # Stop details feature

OnBoardTests/
└── NearbyModelTests.swift
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
