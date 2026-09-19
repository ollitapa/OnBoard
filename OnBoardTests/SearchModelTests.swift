import Testing
import Foundation
@testable import OnBoard

@MainActor
struct SearchModelTests {

    // MARK: - search(named:)

    @Test func searchSuccess() async throws {
        // Given: a controlled dataset where "slu" matches only "Slussen".
        let network = MockTrafiklabService(stopGroups: Self.searchDataset)
        let model = SearchModel()

        // When
        await model.search(named: "slu", network: network)

        // Then
        let names = model.results.map(\.name)
        #expect(names == ["Slussen"])
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    @Test func searchMatchesMultipleBySubstring() async throws {
        // Given: a controlled dataset where "l" matches both stop names.
        let network = MockTrafiklabService(stopGroups: Self.searchDataset)
        let model = SearchModel()

        // When
        await model.search(named: "l", network: network)

        // Then: results keep the configured (busiest-first) order.
        let names = model.results.map(\.name)
        #expect(names == ["Slussen", "Odenplan"])
        #expect(model.failure == nil)
    }

    @Test func searchExactMatch() async throws {
        // Given
        let network = MockTrafiklabService(stopGroups: Self.searchDataset)
        let model = SearchModel()

        // When
        await model.search(named: "Odenplan", network: network)

        // Then
        let names = model.results.map(\.name)
        #expect(names == ["Odenplan"])
        #expect(model.failure == nil)
    }

    @Test func searchNoMatches() async throws {
        // Given
        let network = MockTrafiklabService(stopGroups: Self.searchDataset)
        let model = SearchModel()

        // When
        await model.search(named: "zzz", network: network)

        // Then
        #expect(model.results == [])
        #expect(model.failure == nil)
    }

    @Test func searchBlankQueryClearsWithoutRequest() async throws {
        // Given: a model with prior recents. A blank query returns early
        // before any request is made, so results clear and no failure is set.
        let network = MockTrafiklabService(stopGroups: Self.searchDataset)
        let model = SearchModel()
        model.recordRecent("Medborgarplatsen")

        // When
        await model.search(named: "   ", network: network)

        // Then
        #expect(model.results == [])
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    @Test func searchNetworkError() async throws {
        // Given: a network with no handlers throws NoResponseConfigured, which
        // surfaces as a failure rather than an empty success.
        let network = MockNetwork()
        let model = SearchModel()

        // When
        await model.search(named: "Slussen", network: network)

        // Then
        #expect(model.results == [])
        #expect(model.failure != nil)
    }

    @Test func searchInvalidJSON() async throws {
        // Given: a handler that returns non-matching JSON for the search path.
        var network = MockNetwork()
        network.registerHandler { request in
            if request.url?.path.contains("/stops/name/") == true {
                return MockNetwork.makeResponse(json: #"{"invalid":"json"}"#, statusCode: 200)
            }
            return nil
        }
        let model = SearchModel()

        // When
        await model.search(named: "Slussen", network: network)

        // Then
        #expect(model.results == [])
        #expect(model.failure != nil)
    }

    @Test func searchAfterErrorReplacesResultsOnSuccess() async throws {
        // Given: a failed search leaves a failure string.
        let failingNetwork = MockNetwork()
        let model = SearchModel()
        await model.search(named: "Slussen", network: failingNetwork)
        #expect(model.failure != nil)

        // When: a subsequent successful search clears the failure.
        let network = MockTrafiklabService(stopGroups: Self.searchDataset)
        await model.search(named: "Slussen", network: network)

        // Then
        #expect(model.failure == nil)
        let names = model.results.map(\.name)
        #expect(names == ["Slussen"])
    }

    @Test func cancelledSearchLeavesLoadingFlagToReplacementTask() async throws {
        // Given: a search in flight whose replacement is already loading. The
        // replacement sets `isLoading` before the cancelled task resumes.
        let network = MockTrafiklabService(stopGroups: Self.searchDataset)
        let model = SearchModel()
        model.isLoading = true

        // When: a cancelled task runs the same method (as `.task(id:)` does to
        // the previous query's task when the text changes).
        let cancelled = Task { await model.search(named: "Slussen", network: network) }
        cancelled.cancel()
        await cancelled.value

        // Then: the cancelled run did not clobber the replacement's flag.
        #expect(model.isLoading == true)
    }

    // MARK: - recents

    @Test func recordRecentPrependsAndDedupes() {
        let model = SearchModel()
        model.recordRecent("Slussen")
        model.recordRecent("Odenplan")

        // When: recording an existing term moves it to the front.
        model.recordRecent("Slussen")

        // Then
        #expect(model.recents == ["Slussen", "Odenplan"])
    }

    @Test func recordRecentIgnoresBlank() {
        let model = SearchModel()
        model.recordRecent("   ")

        #expect(model.recents == [])
    }

    @Test func recordRecentCapsAtLimit() {
        let model = SearchModel()
        for index in 0..<SearchModel.recentLimit + 3 {
            model.recordRecent("Stop \(index)")
        }

        #expect(model.recents.count == SearchModel.recentLimit)
        // The most recent entries are kept (highest indices at the front).
        #expect(model.recents.first == "Stop \(SearchModel.recentLimit + 2)")
    }

    @Test func clearRecentsEmptiesList() {
        let model = SearchModel()
        model.recordRecent("Slussen")
        model.recordRecent("Odenplan")

        model.clearRecents()

        #expect(model.recents == [])
    }

    // MARK: - Helpers

    /// A small, ordered set of stop groups for tests that need a controlled,
    /// predictable dataset (busiest first, matching the API's ordering).
    static let searchDataset: [StopGroup] = [
        StopGroup(
            id: "740000002",
            name: "Slussen",
            area_type: "META_STOP",
            average_daily_stop_times: 1200,
            transport_modes: ["BUS", "METRO"],
            stops: [StopRef(id: "740000002", name: "Slussen", lat: 59.3199, lon: 18.0717)]
        ),
        StopGroup(
            id: "740000004",
            name: "Odenplan",
            area_type: "META_STOP",
            average_daily_stop_times: 950,
            transport_modes: ["BUS", "TRAIN"],
            stops: [StopRef(id: "740000004", name: "Odenplan", lat: 59.3429, lon: 18.0496)]
        )
    ]
}
