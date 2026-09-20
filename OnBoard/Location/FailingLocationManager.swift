import Foundation
import CoreLocation

/// A ``LocationManager`` that is pre-authorized but reports a location
/// failure every time updates start, for previews of the location failure
/// state. Mirrors ``FixedLocationManager``'s role for the happy path and
/// lives in the app target (like ``AlwaysLoadingLocationManager``) so the
/// permission modifier's preview can use it directly.
final class FailingLocationManager: LocationManager {

    /// The error delivered to the delegate, standing in for the
    /// `kCLErrorDomain` failures a real manager can report.
    private struct LocationUnavailableError: Error, CustomStringConvertible {
        var description: String { "Location unavailable" }
    }

    let authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse

    /// The delegate the manager forwards the failure to.
    weak var locationDelegate: (any LocationManagerDelegate)?

    func requestWhenInUseAuthorization() {}

    func startUpdatingLocation() {
        locationDelegate?.locationManager(
            self,
            didFailWithError: LocationUnavailableError()
        )
    }

    func stopUpdatingLocation() {}
}
