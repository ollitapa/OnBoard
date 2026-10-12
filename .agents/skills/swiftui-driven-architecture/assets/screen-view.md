# Template: screen view

`<Feature>/<Feature>View.swift`

Dependencies come from the environment, the model is `@State` with an inline
default, the load runs from `.task(id:)`, and every sub-view is a real struct.

```swift
import SwiftUI

struct FeatureView: View {

    // Dependencies
    @Environment(\.network) var network
    @Environment(LocationAuthorization.self) private var location

    // Model — inline default, never State(initialValue:)
    @State var model = FeatureModel()

    var body: some View {
        Group {
            if let failure = model.failure {
                UnavailableScreen(
                    title: "Couldn't load rows",
                    systemImage: "wifi.exclamationmark",
                    message: failure
                )
            } else if model.rows.isEmpty {
                if model.isLoading {
                    LoadingIndicator()
                } else {
                    UnavailableScreen(
                        title: "Nothing here yet",
                        systemImage: "mappin.and.ellipse",
                        message: "…"
                    )
                }
            } else {
                FeatureRowsList(rows: model.rows, failure: model.failure)
            }
        }
        .navigationTitle("Feature")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
        .task(id: location.coordinate) {
            guard let coordinate = location.coordinate else { return }
            await model.loadRows(network: network, id: coordinate.id)
        }
    }
}

/// A real struct, not a `private var list: some View` — SwiftUI can then skip
/// this subtree when its inputs are unchanged.
private struct FeatureRowsList: View {
    let rows: [Row]
    /// Most recent refresh failure; while non-nil the rows are stale.
    let failure: String?

    var body: some View {
        List(rows) { row in
            NavigationLink(value: row) {
                FeatureRow(row: row)
            }
            .listRowBackground(Color.panel)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .overlay(alignment: .bottom) {
            if failure != nil {
                Text("Couldn't refresh — showing the last update")
                    .font(.caption)
                    .foregroundStyle(.inkSoft)
                    .padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: failure)
    }
}

private struct FeatureRow: View {
    let row: Row

    var body: some View { ... }
}

#Preview("Default") {
    @Previewable @State var network: NetworkProtocol = mockNetwork()
    @Previewable @State var locationModel = previewLocationAuthorization()

    NavigationStack {
        FeatureView()
    }
    .environment(\.network, network)
    .environment(locationModel)
}
```

## If the view reads `@Environment(\.modelContext)`

The preview **must** publish a container, or the view traps:

```swift
#Preview {
    @Previewable @State var modelContainer: ModelContainer = mockModelContainer()
    FeatureView()
        .modelContainer(modelContainer)
}
```

## Search-as-you-type variant

```swift
@State private var query = ""

.searchable(text: $query, prompt: "Search stops")
.task(id: query) {
    await model.search(named: query, network: network)
}
```

Debounce inside the model, never with `.onChange` + `Task`.
