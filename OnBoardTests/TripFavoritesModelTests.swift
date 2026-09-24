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
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        #expect(model.contains(Self.route()) == true)
    }

    @Test func containsIsFalseAfterRemove() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        #expect(model.contains(Self.route()) == false)
    }

    @Test func containsKeysOffTripIdAndStartDate() async throws {
        // The same trip id on another day is a different journey, so both
        // can be saved at once; identity matches `RouteDetails.id`.
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-02"), endDate: Self.inAnHour, context: container.mainContext)
        #expect(model.contains(Self.route(tripId: "900001", startDate: "2099-01-01")))
        #expect(model.contains(Self.route(tripId: "900001", startDate: "2099-01-02")))
    }

    // MARK: - toggle

    @Test func toggleAddsTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // When
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        // Then
        #expect(model.trips.map(\.snapshot) == [
            TripFavoriteSnapshot(
                id: "900001-2099-01-01",
                tripId: "900001",
                startDate: "2099-01-01",
                lineLabel: "3",
                direction: "Karolinska sjukhuset",
                transportModeRaw: "BUS",
                endDate: Self.inAnHour
            )
        ])
        #expect(model.failure == nil)
    }

    @Test func toggleRemovesExistingTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(
            Self.route(tripId: "900002", lineLabel: "7", direction: "Ropsten"),
            endDate: Self.inAnHour,
            context: container.mainContext
        )
        // When
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        // Then
        #expect(model.trips.map(\.snapshot) == [
            TripFavoriteSnapshot(
                id: "900002-2099-01-01",
                tripId: "900002",
                startDate: "2099-01-01",
                lineLabel: "7",
                direction: "Ropsten",
                transportModeRaw: "BUS",
                endDate: Self.inAnHour
            )
        ])
    }

    @Test func toggleDoesNotDuplicateTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(Self.route(lineLabel: "55"), endDate: Self.inAnHour, context: container.mainContext)
        // Then: still one entry, id-keyed; toggle removed then re-added.
        #expect(model.trips.count == 1)
        #expect(model.trips.first?.id == "900001-2099-01-01")
    }

    @Test func toggleUpdatesFieldsWhenReAdding() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext) // remove
        // When
        model.toggle(Self.route(direction: "Ropsten"), endDate: Self.inAnHour, context: container.mainContext)
        // Then
        #expect(model.trips.first?.direction == "Ropsten")
    }

    @Test func toggleKeepsTripsSortedNewestFirst() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // Insert the "older" trip first, then a moment later the newer one,
        // so the two savedAt timestamps differ.
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), endDate: Self.inAnHour, context: container.mainContext)
        try await Task.sleep(for: .milliseconds(10))
        model.toggle(Self.route(tripId: "900002", startDate: "2099-01-01"), endDate: Self.inAnHour, context: container.mainContext)
        // Then: the list is kept newest-first, not in insertion order.
        #expect(model.trips.map(\.tripId) == ["900002", "900001"])
    }

    // MARK: - remove

    @Test func removeIsNoOpForUnknownId() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        // When
        model.remove("999-2099-01-01", context: container.mainContext)
        // Then
        #expect(model.trips.map(\.tripId) == ["900001"])
    }

    @Test func removeDeletesTrip() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(Self.route(tripId: "900002", startDate: "2099-01-01"), endDate: Self.inAnHour, context: container.mainContext)
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
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        try container.mainContext.save()
        // Then: a fresh model reading the same context sees the saved trip.
        let reader = TripFavoritesModel()
        reader.loadTripFavorites(context: container.mainContext)
        #expect(reader.trips.map(\.tripId) == ["900001"])
        #expect(reader.trips.first?.endDate == Self.inAnHour)
    }

    @Test func removePersistsToStorage() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.toggle(Self.route(tripId: "900001", startDate: "2099-01-01"), endDate: Self.inAnHour, context: container.mainContext)
        model.toggle(Self.route(tripId: "900002", startDate: "2099-01-01"), endDate: Self.inAnHour, context: container.mainContext)
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
        model.toggle(Self.route(), endDate: Self.inAnHour, context: container.mainContext)
        try container.mainContext.save()
        let reader = TripFavoritesModel()
        reader.loadTripFavorites(context: container.mainContext)
        #expect(reader.trips.map(\.tripId) == ["900001"])
    }

    // MARK: - Live/finished split

    @Test func activeTripsAreThoseWhoseEndHasNotPassed() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(tripId: "900001"), endDate: now.addingTimeInterval(30 * 60), context: container.mainContext)
        model.toggle(Self.route(tripId: "900002"), endDate: now.addingTimeInterval(-30 * 60), context: container.mainContext)
        // Then
        #expect(model.activeTrips.map(\.tripId) == ["900001"])
        #expect(model.inactiveTrips.map(\.tripId) == ["900002"])
        #expect(model.finishedCount == 1)
    }

    @Test func tripsWithoutEndDateReadAsLive() async throws {
        // A trip starred before its schedule loaded has no end date; it
        // reads as live so it is never shunted or cleaned on a guess.
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(tripId: "900001"), endDate: nil, context: container.mainContext)
        // Then
        #expect(model.activeTrips.map(\.tripId) == ["900001"])
        #expect(model.inactiveTrips == [])
        #expect(model.finishedCount == 0)
    }

    @Test func finishedTripIsLiveAgainAtEarlierNow() {
        // The split is derived from the end date and the clock, so a trip
        // that has finished "now" was live a minute ago — the model holds
        // no refresh state to go stale.
        let trip = TripFavorite(
            tripId: "900001",
            startDate: "2099-01-01",
            lineLabel: "3",
            direction: "Karolinska sjukhuset",
            transportMode: "BUS",
            endDate: now
        )
        #expect(trip.isActive(now: now.addingTimeInterval(-60)) == true)
        #expect(trip.isActive(now: now.addingTimeInterval(60)) == false)
    }

    // MARK: - Stale-trip cleanup

    @Test func cleanStaleTripsRemovesFinishedTripsOnly() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(tripId: "900001"), endDate: now.addingTimeInterval(-30 * 60), context: container.mainContext)
        model.toggle(Self.route(tripId: "900002"), endDate: now.addingTimeInterval(30 * 60), context: container.mainContext)
        // When
        model.cleanStaleTrips(context: container.mainContext, now: now)
        // Then: only the running trip remains, and the removal persists.
        #expect(model.trips.map(\.tripId) == ["900002"])
        #expect(model.finishedCount == 0)
        try container.mainContext.save()
        let reader = TripFavoritesModel()
        reader.loadTripFavorites(context: container.mainContext)
        #expect(reader.trips.map(\.tripId) == ["900002"])
    }

    @Test func cleanStaleTripsIsNoOpWhenNothingIsFinished() async throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        model.loadTripFavorites(context: container.mainContext)
        model.toggle(Self.route(), endDate: now.addingTimeInterval(30 * 60), context: container.mainContext)
        // When
        model.cleanStaleTrips(context: container.mainContext, now: now)
        // Then
        #expect(model.trips.map(\.tripId) == ["900001"])
    }

    @Test func cleanStaleTripsIsNoOpWhenStoreNotLoaded() throws {
        let container = try makeContainer()
        let model = TripFavoritesModel()
        // `stored` is nil before loadTripFavorites; clean must not crash.
        model.cleanStaleTrips(context: container.mainContext, now: now)
        #expect(model.trips == [])
    }

    // MARK: - Presentation

    @Test func routeDetailsCarriesSavedFields() {
        let trip = TripFavorite(
            tripId: "900001",
            startDate: "2099-01-01",
            lineLabel: "3",
            direction: "Karolinska sjukhuset",
            transportMode: "BUS",
            endDate: now
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
            transportMode: "BUS",
            endDate: now
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

    /// The instant the suite's end dates are anchored to. A real `now` (not
    /// a fixed epoch), because the derived properties — `activeTrips`,
    /// `inactiveTrips`, `finishedCount` — classify against the live clock;
    /// the ±30-minute offsets used in tests dwarf any drift within a run.
    private static let now = Date()

    /// An end date still in the future at the live clock, so a saved trip
    /// with it reads as live.
    private static var inAnHour: Date { now.addingTimeInterval(60 * 60) }
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
            transportModeRaw: transportModeRaw,
            endDate: endDate
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
    let endDate: Date?
}
