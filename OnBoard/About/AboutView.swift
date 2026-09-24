import SwiftUI

/// The About tab: app description and the attribution for the data sources
/// the app is built on (Trafiklab / Samtrafiken).
struct AboutView: View {
    private let trafiklabURL = URL(string: "https://developer.trafiklab.se")!
    private let samtrafikenURL = URL(string: "https://www.samtrafiken.se")!
    private let creatorURL = URL(string: "https://www.linkedin.com/in/olli-tapaninen")!

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(.aboutAppName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.ink)
                    Text(.aboutTagline)
                        .font(.subheadline)
                        .foregroundStyle(.inkSoft)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.panel)
            }

            Section(.aboutCreatedBy) {
                Link(destination: creatorURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                            .foregroundStyle(.accent)
                        Text(.aboutCreatorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ink)
                    }
                }
                .listRowBackground(Color.panel)
            }

            Section(.aboutData) {
                Text(.aboutDataMessage)
                    .font(.subheadline)
                    .foregroundStyle(.inkSoft)
                    .listRowBackground(Color.panel)

                Link(.aboutVisitTrafiklab, destination: trafiklabURL)
                    .foregroundStyle(.accent)
                    .listRowBackground(Color.panel)

                Link(.aboutVisitSamtrafiken, destination: samtrafikenURL)
                    .foregroundStyle(.accent)
                    .listRowBackground(Color.panel)
            }

            Section(.aboutApisUsed) {
                ForEach(Self.apiNames, id: \.self) { name in
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.ink)
                        .listRowBackground(Color.panel)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.paper)
        .navigationTitle(.tabAbout)
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
