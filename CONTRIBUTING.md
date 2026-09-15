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

- **No code comments**: Avoid adding comments in code files
- **Follow existing patterns**: Match the repository's existing style and architecture
- **Small changes**: Make the smallest correct change that solves the problem

## Project Structure

```
OnBoard/
├── Network/              # Network layer
│   ├── NetworkProtocol.swift
│   ├── NetworkDependency.swift
│   ├── LiveNetwork.swift
│   └── MockNetwork.swift
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
