import SwiftUI
import SwiftData

/// The Favourites tab ("Step 4 → Save a stop → skip the search next time" in
/// `Designs/storyboard.html`).
///
/// Shows the saved stops as rows matching the storyboard's `fav-row`: a star,
/// the stop name, and a "Lines …" subtitle, plus a dashed empty hint when no
/// stops are saved. Tapping a row opens the stop's live departure board
/// (``StopDetailsView``). The view is driven by ``FavoritesModel`` and reads
/// its shared model from the SwiftUI environment (`@Environment(FavoritesModel.self)`),
/// so the Stop board's star toggle and this tab mutate the same list.
struct FavoritesView: View {
    @Environment(FavoritesModel.self) private var favoritesModel

    var body: some View {
        FavoritesContent(model: favoritesModel)
            .navigationTitle("Favourites")
    }
}

/// The favourites list and its empty/error/loading states, extracted as a
/// struct taking only the model it needs so SwiftUI can skip re-rendering it
/// when unrelated parent state changes.
private struct FavoritesContent: View {
    @Environment(\.modelContext) var modelContext
    let model: FavoritesModel

    var body: some View {
        Group {
            if let failure = model.failure {
                ContentUnavailableView {
                    Label("Couldn't load favourites", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.ink)
                } description: {
                    Text(failure)
                        .foregroundStyle(.inkSoft)
                }
            } else if model.isLoading {
                ProgressView()
                    .tint(.accent)
            } else if model.favorites.isEmpty == true {
                FavoritesEmptyHint()
            } else {
                FavoritesList(model: model)
            }
        }
        .onAppear {
            model.loadFavorites(context: modelContext)
        }
    }
}

/// The plain list of saved-stop rows. Swipe-to-delete removes a stop from
/// the favourites list via the shared model.
private struct FavoritesList: View {
    @Environment(\.modelContext) var modelContext
    let model: FavoritesModel

    var body: some View {
        List {
            ForEach(model.favorites) { favorite in
                NavigationLink(value: favorite) {
                    FavoriteRow(favorite: favorite)
                }
            }
            .onDelete { indexSet in
                let ids = indexSet.map { model.favorites[$0].id }
                for id in ids {
                    model.remove(id, context: modelContext)
                }
            }
        }
        .listStyle(.plain)
        .listRowBackground(Color.panel)
        .background(Color.paper)
        .navigationDestination(for: Favorite.self) { favorite in
            StopDetailsView(stopId: favorite.id, stopName: favorite.name)
        }
    }
}

/// One `fav-row` from the storyboard: a star, the stop name, and a "Lines …"
/// subtitle.
private struct FavoriteRow: View {
    let favorite: Favorite

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "star.fill")
                .foregroundStyle(.star)
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(favorite.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                if !favorite.lineSummary.isEmpty {
                    Text(favorite.lineSummary)
                        .font(.caption)
                        .foregroundStyle(.inkSoft)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
    }
}

/// The dashed empty hint shown when no stops are saved, matching the
/// storyboard's `empty-hint`. English per the app's English-only chrome.
private struct FavoritesEmptyHint: View {
    var body: some View {
        ContentUnavailableView {
            Label("No favourites yet", systemImage: "star")
                .foregroundStyle(.ink)
        } description: {
            Text("Add stops by tapping the star on any stop page.")
                .foregroundStyle(.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Favourites") {
    @Previewable @State var model = FavoritesModel()

    NavigationStack {
        FavoritesView()
    }
    .environment(model)
    .modelContainer(mockModelContainer())
    .environment(\.network, mockNetwork())
}

#Preview("Empty") {
    @Previewable @State var model = FavoritesModel()

    NavigationStack {
        FavoritesView()
    }
    .environment(model)
    .modelContainer(emptyModelContainer())
}
