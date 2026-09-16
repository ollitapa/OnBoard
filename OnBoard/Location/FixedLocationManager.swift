import Foundation
import CoreLocation

/// A ``LocationManager`` that is pre-authorized with a fixed coordinate,
/// used only when `--skip-location-permission` is passed at launch so the
/// Nearby tab renders stops in UI tests where the simulator can't grant real
/// CoreLocation permission.
///
/// Reports a single granted status and a single coordinate; update requests
/// are no-ops. This lives in the app target (not the test target) because the
/// permission modifier reads it at launch.
final class FixedLocationManager: LocationManager {

    let authorizationStatus: CLAuthorizationStatus

    weak var locationDelegate: (any LocationManagerDelegate)?

    /// The coordinate delivered to the delegate after updates start.
    private let coordinate: CLLocationCoordinate2D

    /// Whether `startUpdatingLocation` has been called, to deliver the
    /// coordinate exactly once.
    private var delivered = false

    init(
        authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse,
        coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 59.31, longitude: 18.07)
    ) {
        self.authorizationStatus = authorizationStatus
        self.coordinate = coordinate
    }

    func requestWhenInUseAuthorization() {}

    func startUpdatingLocation() {
        guard !delivered else { return }
        delivered = true
        locationDelegate?.locationManager(
            self,
            didUpdateLocations: [
                CLLocation(
                    coordinate: coordinate,
                    altitude: 0,
                    horizontalAccuracy: 5,
                    verticalAccuracy: 5,
                    timestamp: Date()
                )
            ]
        )
    }

    func stopUpdatingLocation() {}
}
