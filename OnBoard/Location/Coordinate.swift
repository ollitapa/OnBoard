import CoreLocation

/// An app-owned WGS84 coordinate value that is `Equatable` and `Hashable`,
/// so SwiftUI `.task(id:)` and other identity-driven modifiers can key off it
/// without retroactively conforming `CLLocationCoordinate2D` to `Equatable`.
///
/// `CLLocationCoordinate2D` is a non-Sendable, non-`Equatable` C-imported
/// struct; this wrapper is a value type the app can compare and hash directly.
struct Coordinate: Equatable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}
