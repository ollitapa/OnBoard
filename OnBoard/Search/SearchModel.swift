import Foundation
import Observation

/// The view model for the Search tab ("Tab: Search" in
/// `Designs/storyboard.html`).
///
/// Owns the search lifecycle, mirroring ``NearbyModel`` and
/// ``StopDetailsModel``: `@MainActor @Observable`, builds a `Trafiklab` client
/// from the injected network so tests can substitute a mock service, and
/// surfaces transport errors as a `failure` string rather than throwing. The
/// view owns the search text (via SwiftUI's `.searchable`) and asks the model
/// to run a query; a blank query clears the results so the view can show the
/// "Recent searches" section instead.
@MainActor
@Observable
final class SearchModel {

    /// The most recent transport error, if the last search failed.
    var failure: String?

    /// Whether a search is currently in progress.
    var isLoading: Bool = false

    /// The stop groups matching the current query, in API order (busiest first).
    var results: [StopGroup] = []

    /// Recently entered search terms, most recent first, deduplicated and
    /// capped. Shown in the "Recent searches" section when the query is blank.
    private(set) var recents: [String] = []

    /// The maximum number of recent searches kept.
    static let recentLimit = 8

    init() {}

    /// Searches stop groups by name, or clears the results for a blank query.
    /// - Parameters:
    ///   - query: The search text; whitespace-only and empty queries clear the
    ///     results without a request.
    ///   - network: The transport used to perform requests; the model builds a
    ///     `Trafiklab` client from it so tests can inject a mock service.
    func search(named query: String, network: some NetworkProtocol) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            failure = nil
            isLoading = false
            return
        }

        isLoading = true
        // A cancellation always hands the loading flag to the task that
        // replaced us (`.task(id:)` starts the new task before cancelling the
        // old one), so bail out early and leave the flag alone: setting it
        // here would clobber the replacement's `true` with a stale `false`.
        defer { if !Task.isCancelled { isLoading = false } }

        do {
            // This delay is a simple debounce to avoid hammering the API with every keystroke.
            try await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }

            let api = Trafiklab(network: network)
            let response = try await api.searchStops(named: trimmed)
            guard !Task.isCancelled else { return }
            results = response.stop_groups
            failure = nil
        } catch is CancellationError {
            // Task was cancelled, ignore.
        }  catch {
            results = []
            failure = String(describing: error)
        }
    }

    /// Records a search term among the recents, moving it to the front,
    /// deduplicating, and capping to ``recentLimit``.
    /// - Parameter query: The search text to remember; blank terms are ignored.
    func recordRecent(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        recents.removeAll { $0 == trimmed }
        recents.insert(trimmed, at: 0)
        if recents.count > Self.recentLimit {
            recents.removeLast(recents.count - Self.recentLimit)
        }
    }

    /// Removes all recorded recent searches.
    func clearRecents() {
        recents = []
    }
}
