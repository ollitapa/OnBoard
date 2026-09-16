import Foundation
import CoreLocation
import Observation

/// The authorization state the location permission flow can be in.
///
/// Mirrors `CLAuthorizationStatus`, but adds a `notDetermined` value that
/// separates "we have not asked yet" from "the user answered", which the
/// permission view modifier uses to decide whether to show the explanation
/// view.
enum LocationAuthorizationState: Equatable, Sendable {
    /// The app has not yet requested authorization.
    case notDetermined
    /// The user denied permission (either at the prompt or in Settings).
    case denied
    /// Permission granted for the app's foreground use only.
    case authorizedWhenInUse
    /// Permission granted including background use.
    case authorizedAlways
}

/// An observable model that drives the location permission screen and exposes
/// the device's current coordinate to views via the SwiftUI environment.
///
/// Owns a `CLLocationManager`, requests authorization on demand (triggered by
/// the `LocationButton` in the permission view), and streams `CLLocation`
/// updates into ``coordinate``. Tests inject a ``LocationManaging`` mock so the
/// authorization lifecycle can be exercised without CoreLocation.
@MainActor
@Observable
final class LocationAuthorization: NSObject {

    /// The current authorization state.
    private(set) var status: LocationAuthorizationState = .notDetermined

    /// The most recent WGS84 coordinate, or `nil` while permission is pending
    /// or no fix is available yet.
    private(set) var coordinate: CLLocationCoordinate2D?

    /// The most recent location error, surfaced for diagnostics.
    private(set) var failure: String?

    private let manager: any LocationManaging

    /// Creates a model backed by a real `CLLocationManager`, bridged through
    /// `LiveLocationManager` so the manager's `CLLocationManagerDelegate`
    /// callbacks are forwarded onto ``LocationManagingDelegate``.
    override init() {
        self.manager = LiveLocationManager()
        super.init()
        self.manager.locationDelegate = self
        self.status = Self.state(from: manager.authorizationStatus)
    }

    /// Creates a model backed by the given manager. Use this in tests to
    /// inject a mock that drives the authorization lifecycle deterministically.
    /// - Parameter manager: A `LocationManaging` instance (real or mock).
    init(manager: any LocationManaging) {
        self.manager = manager
        super.init()
        self.manager.locationDelegate = self
        self.status = Self.state(from: manager.authorizationStatus)
    }

    /// Requests authorization from the system. Call this from the
    /// `LocationButton` (Apple forbids offering "no" through any UI other than
    /// the system prompt). When permission is granted the manager
    /// automatically starts delivering updates into ``coordinate``.
    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Starts standard location updates once permission has been granted.
    /// Safe to call before authorization; it is a no-op until the status is
    /// `.authorizedWhenInUse` or `.authorizedAlways`.
    func startUpdating() {
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        manager.startUpdatingLocation()
    }

    /// Stops location updates.
    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    /// Maps a `CLAuthorizationStatus` onto the app's authorization state.
    private static func state(from status: CLAuthorizationStatus) -> LocationAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted, .denied:
            return .denied
        case .authorizedAlways:
            return .authorizedAlways
        case .authorizedWhenInUse:
            return .authorizedWhenInUse
        @unknown default:
            return .denied
        }
    }
}

extension LocationAuthorization: LocationManagingDelegate {

    nonisolated func locationManager(_ manager: any LocationManaging, didChangeAuthorization status: CLAuthorizationStatus) {
        MainActor.assumeIsolated {
            self.status = Self.state(from: status)
            self.startUpdating()
        }
    }

    nonisolated func locationManager(_ manager: any LocationManaging, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            self.coordinate = locations.last?.coordinate
            self.failure = nil
        }
    }

    nonisolated func locationManager(_ manager: any LocationManaging, didFailWithError error: any Error) {
        MainActor.assumeIsolated {
            self.failure = String(describing: error)
        }
    }
}

/// The usage description the app declares in its Info.plist, surfaced for the
/// permission explanation view. Returns an empty string when the key is
/// absent so previews and tests don't crash on an unconfigured bundle.
extension LocationAuthorization {

    /// The value of the `NSLocationWhenInUseUsageDescription` Info.plist key.
    static var usageDescription: String {
        (Bundle.main.infoDictionary?["NSLocationWhenInUseUsageDescription"] as? String) ?? ""
    }
}
