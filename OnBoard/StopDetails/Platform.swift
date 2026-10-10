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

    /// The single transport mode serving this platform when every departure
    /// for it uses the same mode, otherwise `nil`. Used as the button label
    /// when the platform is mode-specific (e.g. a tram-only platform).
    func dominantTransportMode(departures: [CallAtLocation]) -> TransportMode? {
        let modes = Set(
            departures
                .filter { $0.stop?.id == id }
                .compactMap { $0.route?.transport_mode }
        )
        return modes.count == 1 ? modes.first : nil
    }
}
