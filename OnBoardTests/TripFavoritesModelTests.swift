import Testing
import Foundation
import SwiftData
@testable import OnBoard

@MainActor
struct TripFavoritesModelTests {
    // MARK: - Loading

    @Test func loadTripFavoritesEmptyStoreStartsEmpty() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // When
        model.loadTripFavorites(context: container.mainContext)
        // Then
        #expect(model.trips == [])
        #expect(model.failure == nil)
        #expect(model.isLoading == false)
    }

    // MARK: - contains

    @Test func containsIsFalseBeforeSave() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        #expect(model.contains(Self.route()) == false)
    }

    @Test func containsIsTrueAfterSave() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), context: container.mainContext)
        #expect(model.contains(Self.route()) == true)
    }

    @Test func containsIsFalseAfterRemove() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), context: container.mainContext)
        model.toggle(Self.route(), context: container.mainContext)
        #expect(model.contains(Self.route()) == false)
    }

    @Test func containsKeysOffTripIdAndStartDate() async throws {
        // The same trip id on another day is a different journey, so both
        // can be saved at once; identity matches `RouteDetails.id`.
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), context: container.mainContext)
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-02"), context: container.mainContext)
        #expect(model.contains(Self.route(tripId: "900001", startDate: "2099-01-01")))
        #expect(model.contains(Self.route(tripId: "900001", startDate: "2099-01-02")))
    }

    // MARK: - toggle

    @Test func toggleAddsTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // When
        model.toggle(Self.route(), context: container.mainContext)
        // Then
        #expect(model.trips.map(\.snapshot) == [
            TripFavoriteSnapshot(
                id: "900001-2099-01-01",
                tripId: "900001",
                startDate: "2099-01-01",
                lineLabel: "3",
                direction: "Karolinska sjukhuset",
                transportModeRaw: "BUS"
            )
        ])
        #expect(model.failure == nil)
    }

    @Test func toggleRemovesExistingTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), context: container.mainContext)
        model.toggle(
            Self.route(tripId: "900002", lineLabel: "7", direction: "Ropsten"),
            context: container.mainContext
        )
        // When
        model.toggle(Self.route(), context: container.mainContext)
        // Then
        #expect(model.trips.map(\.snapshot) == [
            TripFavoriteSnapshot(
                id: "900002-2099-01-01",
                tripId: "900002",
                startDate: "2099-01-01",
                lineLabel: "7",
                direction: "Ropsten",
                transportModeRaw: "BUS"
            )
        ])
    }

    @Test func toggleDoesNotDuplicateTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), context: container.mainContext)
        model.toggle(Self.route(), context: container.mainContext)
        model.toggle(Self.route(lineLabel: "55"), context: container.mainContext)
        // Then: still one entry, id-keyed; toggle removed then re-added.
        #expect(model.trips.count == 1)
        #expect(model.trips.first?.id == "900001-2099-01-01")
    }

    @Test func toggleUpdatesFieldsWhenReAdding() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), context: container.mainContext)
        model.toggle(Self.route(), context: container.mainContext) // remove
        // When
        model.toggle(Self.route(direction: "Ropsten"), context: container.mainContext)
        // Then
        #expect(model.trips.first?.direction == "Ropsten")
    }

    @Test func toggleKeepsTripsSortedNewestFirst() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // Insert the "older" trip first, then a moment later the newer one,
        // so the two savedAt timestamps differ.
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), context: container.mainContext)
        try await Task.sleep(for: .milliseconds(10))
        model.toggle(Self.route(tripId: "900002", startDate: "2099-01-01"), context: container.mainContext)
        // Then: the list is kept newest-first, not in insertion order.
        #expect(model.trips.map(\.tripId) == ["900002", "900001"])
    }

    // MARK: - remove

    @Test func removeIsNoOpForUnknownId() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), context: container.mainContext)
        // When
        model.remove("999-2099-01-01", context: container.mainContext)
        // Then
        #expect(model.trips.map(\.tripId) == ["900001"])
    }

    @Test func removeDeletesTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), context: container.mainContext)
        model.toggle(Self.route(tripId: "900002", startDate: "2099-01-01"), context: container.mainContext)
        // When
        model.remove("900001-2099-01-01", context: container.mainContext)
        // Then
        #expect(model.trips.map(\.tripId) == ["900002"])
    }

    @Test func removeIsNoOpWhenStoreNotLoaded() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // `stored` is nil before loadTripFavorites; remove must not crash.
        model.remove("900001-2099-01-01", context: container.mainContext)
        #expect(model.trips == [])
    }

    // MARK: - Persistence

    @Test func togglePersistsToStorage() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // When
        model.toggle(Self.route(), context: container.mainContext)
        try container.mainContext.save()
        // Then: a fresh model reading the same context sees the saved trip.
        let reader = TripFavoritesModel()
        reader.loadTripFavorites(context: container.mainContext)
        #expect(reader.trips.map(\.tripId) == ["900001"])
    }

    @Test func removePersistsToStorage() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), context: container.mainContext)
        model.toggle(Self.route(tripId: "900002", startDate: "2099-01-01"), context: container.mainContext)
        // When
        model.remove("900001-2099-01-01", context: container.mainContext)
        try container.mainContext.save()
        // Then
        let reader = TripFavoritesModel()
        reader.loadTripFavorites(context: container.mainContext)
        #expect(reader.trips.map(\.tripId) == ["900002"])
    }

    @Test func toggleCreatesStoreOnDemand() async throws {
        // With no seeded StoredTripFavorites, the first toggle inserts one
        // rather than crashing, and the trip is visible through the context.
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), context: container.mainContext)
        try container.mainContext.save()
        let reader = TripFavoritesModel()
        reader.loadTripFavorites(context: container.mainContext)
        #expect(reader.trips.map(\.tripId) == ["900001"])
    }

    // MARK: - Stale-trip cleanup

    @Test func cleanStaleTripsRemovesFinishedTrips() async throws {
        // Given: one trip whose final stop has passed and one still running,
        // served from fixtures with relative timestamps resolved around now.
        let network = MockTrafiklabService(tripsByKey: [
            "900001/2099-01-01": Self.finishedTripJSON,
            "900002/2099-01-01": Self.runningTripJSON
        ])
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), context: container.mainContext)
        model.toggle(Self.route(tripId: "900002", startDate: "2099-01-01"), context: container.mainContext)
        // When
        await model.cleanStaleTrips(network: network, context: container.mainContext)
        // Then: only the running trip remains.
        #expect(model.trips.map(\.tripId) == ["900002"])
        #expect(model.isCleaning == false)
    }

    @Test func cleanStaleTripsKeepsTripWhenScheduleFailsToLoad() async throws {
        // Given: a network with no handlers, so the schedule request throws —
        // the cleanup must keep the trip rather than guess at it.
        let network = MockNetwork()
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(), context: container.mainContext)
        // When
        await model.cleanStaleTrips(network: network, context: container.mainContext)
        // Then
        #expect(model.trips.map(\.tripId) == ["900001"])
    }

    @Test func cleanStaleTripsKeepsTripWithEmptySchedule() async throws {
        // Given: a trip whose fixture serves an empty calls list — never
        // read as finished, so the cleanup keeps it.
        let network = MockTrafiklabService(tripsByKey: [
            "900001/2099-01-01": Self.emptyTripJSON
        ])
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(), context: container.mainContext)
        // When
        await model.cleanStaleTrips(network: network, context: container.mainContext)
        // Then
        #expect(model.trips.map(\.tripId) == ["900001"])
    }

    @Test func cleanStaleTripsIsNoOpWhenNothingIsSaved() async throws {
        let network = MockNetwork()
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        // When
        await model.cleanStaleTrips(network: network, context: container.mainContext)
        // Then
        #expect(model.trips == [])
        #expect(model.isCleaning == false)
    }

    @Test func cleanStaleTripsIsNoOpWhenStoreNotLoaded() async throws {
        let network = MockNetwork()
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // `stored` is nil before loadTripFavorites; clean must not crash.
        await model.cleanStaleTrips(network: network, context: container.mainContext)
        #expect(model.trips == [])
    }

    @Test func cleanStaleTripsPersistsRemoval() async throws {
        let network = MockTrafiklabService(tripsByKey: [
            "900001/2099-01-01": Self.finishedTripJSON
        ])
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(), context: container.mainContext)
        // When
        await model.cleanStaleTrips(network: network, context: container.mainContext)
        try container.mainContext.save()
        // Then
        let reader = TripFavoritesModel()
        reader.loadTripFavorites(context: container.mainContext)
        #expect(reader.trips == [])
    }

    // MARK: - isFinished

    @Test func isFinishedTrueWhenFinalStopPassed() {
        let now = Date()
        let calls = [
            RouteDetailsModelTests.call(stopId: "0", name: "First", scheduledDeparture: RouteDetailsModelTests.past(now, minutes: 30)),
            RouteDetailsModelTests.call(stopId: "1", name: "Final", scheduledDeparture: RouteDetailsModelTests.past(now, minutes: 5))
        ]
        #expect(calls.isFinished(now: now))
    }

    @Test func isFinishedFalseWhenTripHasNotStarted() {
        let now = Date()
        let calls = [
            RouteDetailsModelTests.call(stopId: "0", name: "First", scheduledDeparture: RouteDetailsModelTests.future(now, minutes: 10))
        ]
        #expect(calls.isFinished(now: now) == false)
    }

    @Test func isFinishedFalseWhileVehicleIsOnTheTrack() {
        let now = Date()
        // The vehicle is between stops, heading to the final one.
        let calls = [
            RouteDetailsModelTests.call(stopId: "0", name: "First", scheduledDeparture: RouteDetailsModelTests.past(now, minutes: 10)),
            RouteDetailsModelTests.call(stopId: "1", name: "Final", scheduledDeparture: RouteDetailsModelTests.future(now, minutes: 6))
        ]
        #expect(calls.isFinished(now: now) == false)
    }

    @Test func isFinishedFalseForEmptySchedule() {
        let calls: [TripCall] = []
        #expect(calls.isFinished() == false)
    }

    // MARK: - Presentation

    @Test func routeDetailsCarriesSavedFields() {
        let trip = TripFavorite(
            tripId: "900001",
            startDate: "2099-01-01",
            lineLabel: "3",
            direction: "Karolinska sjukhuset",
            transportMode: "BUS"
        )
        let route = trip.routeDetails
        #expect(route.tripId == "900001")
        #expect(route.startDate == "2099-01-01")
        #expect(route.lineLabel == "3")
        #expect(route.direction == "Karolinska sjukhuset")
        #expect(route.transportMode == "BUS")
        #expect(route.delayMinutes == nil)
    }

    @Test func lineSummaryReadsLineLabel() {
        let trip = TripFavorite(
            tripId: "900001",
            startDate: "2099-01-01",
            lineLabel: "3",
            direction: "Karolinska sjukhuset",
            transportMode: "BUS"
        )
        #expect(trip.lineSummary == "Line 3")
    }

    // MARK: - Helpers

    /// Builds an in-memory `ModelContext` for `StoredTripFavorites`. SwiftData
    /// models are reference types with no value `==`, so tests compare a
    /// `TripFavorite`'s `TripFavoriteSnapshot` rather than the model itself.
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: StoredTripFavorites.self,
            configurations: configuration
        )
    }

    /// A `RouteDetails` for a trip to save, mirroring the value built from a
    /// tapped departure.
    private static func route(
        tripId: String = "900001",
        startDate: String = "2099-01-01",
        lineLabel: String = "3",
        direction: String = "Karolinska sjukhuset"
    ) -> RouteDetails {
        RouteDetails(
            tripId: tripId,
            startDate: startDate,
            lineLabel: lineLabel,
            direction: direction,
            delayMinutes: nil,
            transportMode: "BUS"
        )
    }

    /// A trip whose every stop is in the past: the vehicle has left the
    /// final stop, so the cleanup removes it.
    private static let finishedTripJSON = """
    {
        "timestamp": "2099-01-01T12:00:00",
        "calls": [
            {
                "scheduledArrival": "now-30",
                "scheduledDeparture": "now-30",
                "stop": { "id": "1-0", "name": "Skanstull", "lat": 59.3114, "lon": 18.0745 }
            },
            {
                "scheduledArrival": "now-5",
                "scheduledDeparture": "now-5",
                "stop": { "id": "1-1", "name": "Karolinska sjukhuset", "lat": 59.3372, "lon": 18.0281 }
            }
        ]
    }
    """

    /// A trip mid-journey: the first stop is passed and the final stop is
    /// still ahead, so the cleanup keeps it.
    private static let runningTripJSON = """
    {
        "timestamp": "2099-01-01T12:00:00",
        "calls": [
            {
                "scheduledArrival": "now-10",
                "scheduledDeparture": "now-10",
                "stop": { "id": "1-0", "name": "Skanstull", "lat": 59.3114, "lon": 18.0745 }
            },
            {
                "scheduledArrival": "now+6",
                "scheduledDeparture": "now+6",
                "stop": { "id": "1-1", "name": "Slussen", "lat": 59.3199, "lon": 18.0717 }
            },
            {
                "scheduledArrival": "now+30",
                "scheduledDeparture": "now+30",
                "stop": { "id": "1-2", "name": "Karolinska sjukhuset", "lat": 59.3372, "lon": 18.0281 }
            }
        ]
    }
    """

    /// A trip whose schedule carries no calls: never read as finished, so
    /// the cleanup keeps it.
    private static let emptyTripJSON = """
    {
        "timestamp": "2099-01-01T12:00:00",
        "calls": []
    }
    """
}

// MARK: - Snapshots

private extension TripFavorite {
    /// A value snapshot of the saved trip's persisted fields, for `==`-based
    /// expectations. `TripFavorite` is a SwiftData `@Model` (reference
    /// identity), so tests compare this value instead of the model object.
    var snapshot: TripFavoriteSnapshot {
        TripFavoriteSnapshot(
            id: id,
            tripId: tripId,
            startDate: startDate,
            lineLabel: lineLabel,
            direction: direction,
            transportModeRaw: transportModeRaw
        )
    }
}

/// A value-type snapshot of a `TripFavorite`, so saved trips can be compared
/// in tests, per the repo's snapshot convention for `@Model` classes.
struct TripFavoriteSnapshot: Equatable {
    let id: String
    let tripId: String
    let startDate: String
    let lineLabel: String
    let direction: String
    let transportModeRaw: String?
}
