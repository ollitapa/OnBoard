import Foundation

/// A physical platform within a meta-stop, used for filtering departures.
/// Note: Renamed from `Platform` to avoid collision with `Platform` in TrafiklabAPI.
struct StopPlatform: Identifiable, Hashable, Equatable, Sendable {
    let id: String
    let name: String
    let lat: Double?
    let lon: Double?

    init(from stop: TimetableStop) {
        self.id = stop.id
        self.name = stop.name
        self.lat = stop.lat
        self.lon = stop.lon
    }
}
