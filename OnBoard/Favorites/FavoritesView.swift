import SwiftUI
import SwiftData

/// The Favourites tab ("Step 4 — Save a stop → skip the search next time" in
/// `Designs/storyboard.html`), now carrying the saved journeys too: one
/// combined list with the live trips on top, the stops in the middle, and
/// the inactive trips shunted to the end. Tapping a stop row opens its live
/// departure board (``StopDetailsView``), tapping a trip row re-opens its
/// Live Trip screen (``RouteDetailsView``).
///
/// The view reads the shared ``FavoritesModel`` and ``TripFavoritesModel``
/// from the SwiftUI environment (`@Environment(Model.self)`), so the Stop
/// board's star toggle, the Live Trip screen's trip toggle, and this list
/// all mutate the same state. Each trip section hides itself when empty —
/// typically only the stop rows render.
struct FavoritesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(FavoritesModel.self) private var model
    @Environment(TripFavoritesModel.self) private var tripModel

    var body: some View {
        Group {
            if let failure = model.failure ?? tripModel.failure {
                UnavailableScreen(
                    title: "Couldn't load favourites",
                    systemImage: "wifi.exclamationmark",
                    message: failure
                )
            } else if model.isLoading {
                LoadingIndicator()
            } else if isEmpty {
                FavoritesEmptyHint()
            } else {
                FavoritesList(model: model, tripModel: tripModel)
            }
        }
        .background(Color.paper)
        .navigationTitle("Favourites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if tripModel.finishedCount > 0 {
                    CleanStaleTripsButton(model: tripModel)
                }
            }
        }
        .onAppear {
            model.loadFavorites(context: modelContext)
            tripModel.loadTripFavorites(context: modelContext)
        }
    }

    /// The screen is empty only when there is nothing at all to show: no
    /// stops and no trips. Empty trip sections hide themselves, so this is
    /// driven by the raw counts, not the sectioned lists.
    private var isEmpty: Bool {
        model.favorites.isEmpty && tripModel.trips.isEmpty
    }
}

/// The combined list: the live trips' section on top, the stops in the
/// middle, and the inactive trips' section at the end. Swipe-to-delete
/// removes rows from any section via the shared models.
private struct FavoritesList: View {
    @Environment(\.modelContext) var modelContext
    let model: FavoritesModel
    let tripModel: TripFavoritesModel

    var body: some View {
        List {
            if !tripModel.activeTrips.isEmpty {
                Section("Live trips") {
                    ForEach(tripModel.activeTrips) { trip in
                        NavigationLink(value: trip.routeDetails) {
                            TripFavoriteRow(trip: trip)
                        }
                        .listRowBackground(Color.panel)
                    }
                    .onDelete { indexSet in
                        remove(indexSet, from: tripModel.activeTrips)
                    }
                }
            }
            if !model.favorites.isEmpty {
                Section("Stops") {
                    ForEach(model.favorites) { favorite in
                        NavigationLink(value: favorite) {
                            FavoriteRow(favorite: favorite)
                        }
                        .listRowBackground(Color.panel)
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { model.favorites[$0].id }
                        for id in ids {
                            model.remove(id, context: modelContext)
                        }
                    }
                }
            }
            if !tripModel.inactiveTrips.isEmpty {
                Section("Saved trips") {
                    ForEach(tripModel.inactiveTrips) { trip in
                        NavigationLink(value: trip.routeDetails) {
                            TripFavoriteRow(trip: trip)
                        }
                        .listRowBackground(Color.panel)
                    }
                    .onDelete { indexSet in
                        remove(indexSet, from: tripModel.inactiveTrips)
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color.paper)
        .navigationDestination(for: Favorite.self) { favorite in
            StopDetailsView(stopId: favorite.id, stopName: favorite.name)
        }
        .navigationDestination(for: RouteDetails.self) { route in
            RouteDetailsView(route: route)
        }
    }

    /// Swipe-to-delete for a trip section, whose rows come from the model's
    /// filtered lists rather than the raw aggregate.
    private func remove(_ indexSet: IndexSet, from trips: [TripFavorite]) {
        let ids = indexSet.map { trips[$0].id }
        for id in ids {
            tripModel.remove(id, context: modelContext)
        }
    }
}

/// One `fav-row` from the storyboard: a star, the stop name, and a "Lines …"
/// subtitle.
private struct FavoriteRow: View {
    let favorite: Favorite
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "star.fill")
                .foregroundStyle(.star)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                if !favorite.lineSummary.isEmpty {
                    Text(favorite.lineSummary)
                        .font(.subheadline)
                        .foregroundStyle(.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
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

/// The toolbar button that removes finished trips (whose saved end date
/// has passed) from the list.
private struct CleanStaleTripsButton: View {
    @Environment(\.modelContext) var modelContext
    let model: TripFavoritesModel

    var body: some View {
        Button {
            model.cleanStaleTrips(context: modelContext)
        } label: {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(.inkSoft)
        }
        .accessibilityLabel("Clean finished trips")
    }
}

/// The dashed empty hint shown when nothing is saved, matching the
/// storyboard's `empty-hint`. English per the app's English-only chrome.
private struct FavoritesEmptyHint: View {
    var body: some View {
        UnavailableScreen(
            title: "No favourites yet",
            systemImage: "star",
            message: "Add stops by tapping the star on any stop page."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Stops and trips") {
    @Previewable @State var model = FavoritesModel()
    @Previewable @State var tripModel = TripFavoritesModel()
    NavigationStack {
        FavoritesView()
    }
    .environment(model)
    .environment(tripModel)
    .environment(previewLineColours())
    .modelContainer(mockModelContainer())
    .environment(\.network, mockNetwork())
}

#Preview("Empty") {
    @Previewable @State var model = FavoritesModel()
    @Previewable @State var tripModel = TripFavoritesModel()
    NavigationStack {
        FavoritesView()
    }
    .environment(model)
    .environment(tripModel)
    .modelContainer(emptyModelContainer())
}
