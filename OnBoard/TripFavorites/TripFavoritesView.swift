import SwiftUI
import SwiftData

/// The Trips tab: journeys saved from the Live Trip screen, so the next ride
/// starts one tap away. Mirrors ``FavoritesView``: rows show the line badge
/// with a transport-mode blip and the destination, tapping a row re-opens the
/// Live Trip screen (``RouteDetailsView``), swipe-to-delete removes a saved
/// trip, and a dashed empty hint shows when nothing is saved. Finished trips
/// (whose final stop has passed) are cleaned automatically when the tab
/// opens and via the toolbar's clean button
/// (``TripFavoritesModel.cleanStaleTrips(network:context:)``), so the list
/// doesn't fill up with journeys the vehicle has already completed.
struct TripFavoritesView: View {
    @Environment(TripFavoritesModel.self) private var tripFavoritesModel

    var body: some View {
        TripFavoritesContent(model: tripFavoritesModel)
            .navigationTitle("Trips")
    }
}

/// The saved-trips list and its empty/error/loading states, extracted as a
/// struct taking only the model it needs so SwiftUI can skip re-rendering it
/// when unrelated parent state changes.
private struct TripFavoritesContent: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.network) var network
    let model: TripFavoritesModel

    var body: some View {
        Group {
            if let failure = model.failure {
                UnavailableScreen(
                    title: "Couldn't load saved trips",
                    systemImage: "wifi.exclamationmark",
                    message: failure
                )
            } else if model.isLoading {
                LoadingIndicator()
            } else if model.trips.isEmpty == true {
                TripFavoritesEmptyHint()
            } else {
                TripFavoritesList(model: model)
            }
        }
        .background(Color.paper)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !model.trips.isEmpty {
                    CleanStaleTripsButton(model: model)
                }
            }
        }
        .onAppear {
            model.loadTripFavorites(context: modelContext)
        }
        .task {
            // The cleanup reads the aggregate, and `.task` may start before
            // the first `onAppear` has run, so make sure it's loaded.
            model.loadTripFavorites(context: modelContext)
            await model.cleanStaleTrips(network: network, context: modelContext)
        }
    }
}

/// The plain list of saved-trip rows. Swipe-to-delete removes a trip from
/// the list via the shared model.
private struct TripFavoritesList: View {
    @Environment(\.modelContext) var modelContext
    let model: TripFavoritesModel

    var body: some View {
        List {
            ForEach(model.trips) { trip in
                NavigationLink(value: trip.routeDetails) {
                    TripFavoriteRow(trip: trip)
                }
                .listRowBackground(Color.panel)
            }
            .onDelete { indexSet in
                let ids = indexSet.map { model.trips[$0].id }
                for id in ids {
                    model.remove(id, context: modelContext)
                }
            }
        }
        .listStyle(.plain)
        .background(Color.paper)
        .navigationDestination(for: RouteDetails.self) { route in
            RouteDetailsView(route: route)
        }
    }
}

/// One saved-trip row, reading like the departure it was saved from: a line
/// badge with the transport-mode blip and the destination as the main text.
private struct TripFavoriteRow: View {
    let trip: TripFavorite

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            TripFavoriteLineBadge(
                lineLabel: trip.lineLabel,
                transportMode: trip.transportMode
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.direction)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(trip.lineSummary)
                    .font(.subheadline)
                    .foregroundStyle(.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
    }
}

/// The line badge for a saved trip, mirroring the Stop board's `LineBadge`
/// but taking plain values — a saved trip stores no `CallAtLocation`, and
/// the badge colour keys off the designation + transport mode directly.
private struct TripFavoriteLineBadge: View {
    @Environment(LineColoursModel.self) private var lineColours
    let lineLabel: String
    let transportMode: TransportMode?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(lineLabel)
                .font(.body.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 46, minHeight: 44)
                .background(
                    lineColours.badgeColour(
                        designation: lineLabel,
                        transportMode: transportMode
                    ),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            ModeBlip(mode: transportMode)
        }
    }
}

/// The toolbar button that removes finished trips (whose final stop has
/// passed) from the list, showing a spinner while a cleanup is in flight.
private struct CleanStaleTripsButton: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.network) var network
    let model: TripFavoritesModel

    var body: some View {
        Button {
            Task {
                await model.cleanStaleTrips(network: network, context: modelContext)
            }
        } label: {
            if model.isCleaning {
                LoadingIndicator()
            } else {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(.inkSoft)
            }
        }
        .disabled(model.isCleaning)
        .accessibilityLabel("Clean finished trips")
    }
}

/// The dashed empty hint shown when no trips are saved, matching the
/// Favourites tab's. English per the app's English-only chrome.
private struct TripFavoritesEmptyHint: View {
    var body: some View {
        UnavailableScreen(
            title: "No saved trips yet",
            systemImage: "bus",
            message: "Save a trip by tapping the star on any live trip page."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Saved trips") {
    @Previewable @State var model = TripFavoritesModel()
    NavigationStack {
        TripFavoritesView()
    }
    .environment(model)
    .environment(previewLineColours())
    .modelContainer(mockModelContainer())
    .environment(\.network, mockNetwork())
}

#Preview("Empty") {
    @Previewable @State var model = TripFavoritesModel()
    NavigationStack {
        TripFavoritesView()
    }
    .environment(model)
    .environment(previewLineColours())
    .modelContainer(emptyModelContainer())
}
