import SwiftUI
import SwiftData

/// The Search tab ("Tab: Search" in `Designs/storyboard.html`).
///
/// A focused, full-screen search powered by SwiftUI's `.searchable` modifier:
/// the system-owned search field drives ``SearchModel``, which calls the
/// Trafiklab Stop Lookup endpoint. While the query is blank the screen shows a
/// "Recent searches" section (clock-icon rows, matching the storyboard); once
/// the user types, matching stop groups are listed and a tap opens the stop's
/// live departure board (``StopDetailsView``).
struct SearchView: View {

    @Environment(\.network) private var network

    @State private var model = SearchModel()
    @State private var query = ""

    var body: some View {
        SearchContent(
            model: model,
            query: query,
            onRecentTap: { handleRecent($0) },
            onClearRecents: { model.clearRecents() }
        )
        .navigationTitle(.searchTitle)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: .searchPrompt)
        .onSubmit(of: .search) { handleSubmit() }
        .task(id: query) {
            await model.search(named: query, network: network)
        }
    }

    /// Runs the search and records the term among the recents.
    private func handleSubmit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        model.recordRecent(trimmed)
        Task { await model.search(named: query, network: network) }
    }

    /// Fills the field with a tapped recent search and runs it.
    private func handleRecent(_ recent: String) {
        query = recent
        model.recordRecent(recent)
        Task { await model.search(named: recent, network: network) }
    }
}

/// The search content and its states, extracted as a struct taking only the
/// data it needs so SwiftUI can skip re-rendering it when unrelated parent
/// state changes.
private struct SearchContent: View {

    let model: SearchModel
    let query: String
    let onRecentTap: (String) -> Void
    let onClearRecents: () -> Void

    var body: some View {
        Group {
            if let failure = model.failure {
                UnavailableScreen(
                    title: .searchErrorTitle,
                    systemImage: "wifi.exclamationmark",
                    message: Text(verbatim: failure)
                )
            } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
                RecentsSection(
                    recents: model.recents,
                    onTap: onRecentTap,
                    onClear: onClearRecents
                )
            } else if model.isLoading && model.results.isEmpty {
                LoadingIndicator()
            } else if model.results.isEmpty {
                ContentUnavailableView.search(text: query.trimmingCharacters(in: .whitespaces))
                    .foregroundStyle(.ink, .inkSoft)
            } else {
                SearchResultsList(results: model.results)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.paper)
    }
}

/// The list of matching stop groups. Tapping a row opens the stop's live
/// departure board.
private struct SearchResultsList: View {

    let results: [StopGroup]

    var body: some View {
        List(results) { group in
            NavigationLink(value: group) {
                SearchResultRow(group: group)
            }
            .listRowBackground(Color.panel)
        }
        .listStyle(.plain)
        .background(Color.paper)
        .navigationDestination(for: StopGroup.self) { group in
            StopDetailsView(stopId: group.id, stopName: group.name)
        }
    }
}

/// One search result row: the stop name, a transport-modes subtitle, and the
/// mode icons on the trailing edge.
private struct SearchResultRow: View {

    let group: StopGroup

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                if !group.modeSummary.isEmpty {
                    Text(group.modeSummary)
                        .font(.subheadline)
                        .foregroundStyle(.inkSoft)
                }
            }
            Spacer(minLength: 8)
            ForEach(group.modeIcons, id: \.self) { icon in
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(.inkSoft)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The "Recent searches" section shown when the query is blank, matching the
/// storyboard's clock-icon rows.
private struct RecentsSection: View {

    let recents: [String]
    let onTap: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        if recents.isEmpty {
            UnavailableScreen(
                title: .searchEmptyTitle,
                systemImage: "magnifyingglass",
                message: Text(.searchEmptyMessage)
            )
        } else {
            List {
                Section {
                    ForEach(recents, id: \.self) { recent in
                        Button {
                            onTap(recent)
                        } label: {
                            RecentRow(term: recent)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text(.searchRecentTitle)
                            .foregroundStyle(.ink)
                            .font(.body.weight(.semibold))
                        Spacer()
                        Button(.searchClear, action: onClear)
                            .font(.subheadline)
                            .foregroundStyle(.inkSoft)
                    }
                    .padding(.horizontal, 18)
                }
                .listRowBackground(Color.panel)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .background(Color.paper)
        }
    }
}

/// One recent-search row: a clock icon and the search term.
private struct RecentRow: View {

    let term: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.body)
                .foregroundStyle(.inkSoft)
            Text(term)
                .font(.body)
                .foregroundStyle(.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
    }
}

#Preview("Results") {
    @Previewable @State var favoritesModel = FavoritesModel()
    @Previewable @State var tripFavoritesModel = TripFavoritesModel()

    NavigationStack {
        SearchView()
    }
    .environment(\.network, mockNetwork())
    .environment(favoritesModel)
    .environment(tripFavoritesModel)
    .modelContainer(mockModelContainer())
}

#Preview("Empty") {
    @Previewable @State var favoritesModel = FavoritesModel()
    @Previewable @State var tripFavoritesModel = TripFavoritesModel()

    NavigationStack {
        SearchView()
    }
    .environment(\.network, mockNetwork())
    .environment(favoritesModel)
    .environment(tripFavoritesModel)
    .modelContainer(emptyModelContainer())
}
