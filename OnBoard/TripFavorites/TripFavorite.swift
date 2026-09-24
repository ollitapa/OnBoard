import Foundation
import SwiftData

/// Structure of saved trips stored in the memory.
@Model
final class StoredTripFavorites {
    /// If we want to ever delete all, deleting this object will cascade delete all the saved trips.
    @Relationship(deleteRule: .cascade)
    var trips: [TripFavorite]

    init(trips: [TripFavorite]) {
        self.trips = trips
    }
}

/// A journey saved to the Trips tab from the Live Trip screen ("save this
/// trip → re-open it from the list next time"). Captures just enough to
/// render a row and re-open the stop-by-stop schedule: the trip id + start
/// date (fed to `Trafiklab.trip`), plus the line label, direction, and
/// transport mode shown in the row. The delay isn't captured — it changes
/// minute to minute, so the Live Trip screen re-derives it on load.
/// Uniqueness by trip id + start date is enforced by ``TripFavoritesModel``
/// (which looks saved trips up by id with a predicate rather than via `==`),
/// mirroring ``Favorite``.
@Model
final class TripFavorite: Identifiable {
    /// The trip id + start date ("{tripId}-{startDate}"), used to open the
    /// Live Trip screen and as the row identity; matches `RouteDetails.id`.
    var id: String
    /// `trip.trip_id`, fed to `Trafiklab.trip`.
    var tripId: String
    /// `trip.start_date`, fed to `Trafiklab.trip` (a line runs the same trip
    /// id many times a day; the date disambiguates).
    var startDate: String
    /// The line-badge label, e.g. "55" or "T14", shown in the row's badge.
    var lineLabel: String
    /// The destination text, shown as the row's main text.
    var direction: String
    /// The raw `transport_mode` (`BUS`/`METRO`/…), for the row's mode blip.
    var transportModeRaw: String?
    /// When the trip was saved; the list is kept sorted newest-first.
    var savedAt: Date

    init(
        tripId: String,
        startDate: String,
        lineLabel: String,
        direction: String,
        transportMode: TransportMode?,
        savedAt: Date = Date()
    ) {
        self.id = "\(tripId)-\(startDate)"
        self.tripId = tripId
        self.startDate = startDate
        self.lineLabel = lineLabel
        self.direction = direction
        self.transportModeRaw = transportMode?.rawMode
        self.savedAt = savedAt
    }
}

extension TripFavorite {
    /// The transport mode parsed back from the stored raw value, for the
    /// row's mode blip and badge colour.
    var transportMode: TransportMode? {
        transportModeRaw.map { TransportMode(stringLiteral: $0) }
    }

    /// The navigation value for the Live Trip screen built from the saved
    /// fields, per the repo's presentation-helper convention. The delay isn't
    /// captured at save time, so the header shows no pill until the schedule
    /// reloads.
    var routeDetails: RouteDetails {
        RouteDetails(
            tripId: tripId,
            startDate: startDate,
            lineLabel: lineLabel,
            direction: direction,
            delayMinutes: nil,
            transportMode: transportMode
        )
    }

    /// The row's subtitle: "Line 3" (English, per the app's English-only
    /// chrome). The badge already shows the label; this reads it out for
    /// accessibility and mirrors the favourites row's "Lines …" subtitle.
    var lineSummary: String {
        "Line " + lineLabel
    }
}
