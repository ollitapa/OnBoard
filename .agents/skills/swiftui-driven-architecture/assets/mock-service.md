# Template: fixture-based mock service

`Api/Mock<Service>.swift` — lives in the **app** target so previews and the
UI-test harness can use it.

Configured with wire-shape JSON strings keyed by what the request looks up. The
serving path picks a string and returns its bytes; it never decodes or
re-encodes, so the model under test runs its real production decode.

```swift
import Foundation

/// Serves canned responses for the real endpoint paths the app calls.
/// Fixtures are JSON in the endpoint's wire shape — never hand-built API models.
struct MockMyService: NetworkProtocol {

    /// Keyed by the id the request identifies.
    let rowsById: [String: String]
    /// Keyed by the name the request searches for; the name repeats inside the
    /// JSON, which is fine — the key is what the lookup uses.
    let groupsByName: [String: String]

    init(rowsById: [String: String] = [:], groupsByName: [String: String] = [:]) {
        // Resolve relative timestamp markers once, and validate loudly here so a
        // malformed fixture traps with its name instead of serving empty later.
        self.rowsById = rowsById.mapValues { Self.resolvingTimeMarkers($0) }
        self.groupsByName = groupsByName.mapValues { Self.resolvingTimeMarkers($0) }
        for (key, json) in self.rowsById {
            precondition(Self.isValidJSON(json), "Malformed fixture: rowsById[\(key)]")
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw NoResponseConfigured() }

        // Parse paths with small regex captures, not split-and-index arithmetic.
        if let match = url.path.firstMatch(of: #/rows/([^/]+)/#) {
            let body = rowsById[String(match.1)] ?? "[]"
            return (Data(#"{"items":\#(body)}"#.utf8), Self.ok(url))
        }

        if url.path.hasPrefix("/groups") {
            let name = url.query(named: "q") ?? ""
            // Dictionary fixtures are unordered: serve an explicit, documented
            // order. This deviates from the API's busiest-first ordering.
            let matches = groupsByName
                .filter { $0.key.localizedCaseInsensitiveContains(name) }
                .sorted { $0.key < $1.key }
                .map(\.value)
            return (Data(#"{"groups":[\#(matches.joined(separator: ","))]}"#.utf8), Self.ok(url))
        }

        throw NoResponseConfigured()
    }

    /// Replaces `"now"`, `"now+2"`, `"now-10"` (minutes) with absolute timestamps
    /// so previews and UI tests always show fresh times.
    private static func resolvingTimeMarkers(_ json: String) -> String { ... }
}
```

## Example fixture

Paste a captured response verbatim:

```swift
let service = MockMyService(rowsById: [
    "9021001000001000": """
    [
      {
        "id": "740020101",
        "name": "T-Centralen",
        "scheduled": "now+2",
        "expected": "now+4"
      }
    ]
    """
])
```

## When to use the bare `MockNetwork` instead

Only for request-shape assertions and invalid-JSON tests:

```swift
var network = MockNetwork()
network.registerHandler { request in
    request.url == expectedURL ? MockNetwork.makeResponse(json: "{ not json") : nil
}
...
#expect(network.testableRequests[0] == expectedRequest)
```

A preview wired to a handler-less `MockNetwork` renders `NoResponseConfigured`,
not data.
