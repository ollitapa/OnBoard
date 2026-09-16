import Foundation
import CoreLocation

/// A delegate surface for ``LocationManaging`` that mirrors the subset of
/// `CLLocationManagerDelegate` the app needs, retyped against the protocol so
/// a mock manager can drive a ``LocationAuthorization`` model without
/// CoreLocation.
///
/// Methods are `nonisolated` because `CLLocationManager` delivers its
/// callbacks on the main run loop; conformers route onto `@MainActor` with
/// `MainActor.assumeIsolated`.
protocol LocationManagingDelegate: AnyObject {
    func locationManager(_ manager: any LocationManaging, didChangeAuthorization status: CLAuthorizationStatus)
    func locationManager(_ manager: any LocationManaging, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: any LocationManaging, didFailWithError error: any Error)
}

/// A minimal abstraction over `CLLocationManager` so the authorization
/// lifecycle and coordinate updates can be driven from tests.
///
/// The live conformance forwards to a real `CLLocationManager`; a mock
/// conformance records calls and dispatches delegate callbacks on demand.
protocol LocationManaging: AnyObject {

    /// The current authorization status.
    var authorizationStatus: CLAuthorizationStatus { get }

    /// The object receiving authorization and location callbacks.
    var locationDelegate: (any LocationManagingDelegate)? { get set }

    /// Requests "when in use" authorization from the system.
    func requestWhenInUseAuthorization()

    /// Begins delivering location updates to the delegate.
    func startUpdatingLocation()

    /// Stops delivering location updates.
    func stopUpdatingLocation()
}

/// Live conformance that forwards every call to a real `CLLocationManager`.
///
/// `CLLocationManagerDelegate` callbacks are bridged onto
/// ``LocationManagingDelegate`` so the rest of the app depends only on the
/// protocol. The bridge is a class so it can be retained as the manager's
/// `delegate` while also holding the ``LocationManagingDelegate`` it forwards
/// to.
final class LiveLocationManager: NSObject, LocationManaging {

    private let manager = CLLocationManager()
    private weak var forwardingDelegate: (any LocationManagingDelegate)?

    init() {
        super.init()
        manager.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var locationDelegate: (any LocationManagingDelegate)? {
        get { forwardingDelegate }
        set { forwardingDelegate = newValue }
    }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        manager.stopUpdatingLocation()
    }
}

extension LiveLocationManager: CLLocationManagerDelegate {

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        forwardingDelegate?.locationManager(self, didChangeAuthorization: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        forwardingDelegate?.locationManager(self, didUpdateLocations: locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        forwardingDelegate?.locationManager(self, didFailWithError: error)
    }
}
