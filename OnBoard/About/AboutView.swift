import SwiftUI

/// The About tab: app description and the attribution for the data sources
/// the app is built on (Trafiklab / Samtrafiken).
struct AboutView: View {
    private let trafiklabURL = URL(string: "https://developer.trafiklab.se")!
    private let samtrafikenURL = URL(string: "https://www.samtrafiken.se")!

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OnBoard")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.ink)
                    Text("Follow buses and other public transport in Sweden.")
                        .font(.subheadline)
                        .foregroundStyle(.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.panel)
            }

            Section("Data") {
                Text("Departures, trips, and stop data is provided by Trafiklab, the open data platform for Swedish public transport, operated by Samtrafiken.")
                    .font(.subheadline)
                    .foregroundStyle(.inkSoft)
                    .listRowBackground(Color.panel)

                Link("Visit Trafiklab", destination: trafiklabURL)
                    .foregroundStyle(.accent)
                    .listRowBackground(Color.panel)

                Link("Visit Samtrafiken", destination: samtrafikenURL)
                    .foregroundStyle(.accent)
                    .listRowBackground(Color.panel)
            }

            Section("APIs used") {
                ForEach(Self.apiNames, id: \.self) { name in
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.ink)
                        .listRowBackground(Color.panel)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Color.paper)
        .navigationTitle("About")
    }

    private static let apiNames = [
        "Trafiklab Realtime APIs — Stop Lookup",
        "Trafiklab Realtime APIs — Timetables",
        "Trafiklab Realtime APIs — Trips",
        "ResRobot v2.1 — Nearby Stops",
    ]
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
