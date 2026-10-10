# Template: screen model

`<Feature>/<Feature>Model.swift`

Replace `Nearby` / `Stop` / `loadStops` with the feature's names. Keep the
shape: empty `init()`, dependencies as method parameters, errors as `failure`,
the cancellation-guarded `defer`.

```swift
import Observation
import Foundation

struct Row: Codable, Identifiable, Equatable, Hashable, Sendable {
    var id: String
    var name: String
}

@MainActor
@Observable
final class FeatureModel {

    /// The most recent transport error, if the last load failed.
    var failure: String?

    /// Whether a load is currently in progress.
    var isLoading: Bool = false

    /// Rows from the most recent successful load. Kept (not cleared) when a
    /// refresh fails, so the view shows stale rows with a banner instead of an
    /// empty screen.
    var rows: [Row] = []

    init() {}

    /// - Parameter network: The transport; the model builds its API client from
    ///   it so tests can inject a mock service.
    func loadRows(network: some NetworkProtocol, id: String) async {
        isLoading = true
        // `.task(id:)` starts the replacement task before cancelling this one,
        // so a cancelled load must not clobber the replacement's `true`.
        defer {
            if !Task.isCancelled {
                isLoading = false
            }
        }

        do {
            let api = MyAPI(network: network)
            let response = try await api.rows(id: id)
            rows = response.items.compactMap(Row.init)
            failure = nil

        } catch is CancellationError {
            // Task was cancelled, ignore.
        } catch {
            failure = String(describing: error)
        }
    }
}
```

## Presentation extension

Put display logic on the domain type, in `<Feature>/Row+Feature.swift` next to
its first consumer — not as a `static func` on the model.

```swift
extension Row {
    var distanceLabel: String? { ... }
}
```

## Mutating model that needs storage

Take the `ModelContext` as a parameter; never store one.

```swift
func toggle(_ id: String, name: String, context: ModelContext) { ... }
func loadFavorites(context: ModelContext) { ... }
```
