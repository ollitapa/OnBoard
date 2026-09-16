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
/// ``LocationManagingDelegate`` by an internal `NSObject` helper, so the rest
/// of the app depends only on the protocol. `LiveLocationManager` itself is a
/// plain `final class` (not `NSObject`); only the helper needs `NSObject` to
/// satisfy `CLLocationManagerDelegate`'s `NSObjectProtocol` requirement.
final class LiveLocationManager: LocationManaging {

    private let manager: CLLocationManager
    private let bridge: LocationManagerDelegateBridge
    private weak var forwardingDelegate: (any LocationManagingDelegate)?

    init() {
        let manager = CLLocationManager()
        let bridge = LocationManagerDelegateBridge()
        manager.delegate = bridge
        self.manager = manager
        self.bridge = bridge
        bridge.forwardingDelegateProvider = { [weak self] in self?.forwardingDelegate }
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

/// The `NSObject` adapter that satisfies `CLLocationManagerDelegate` and
/// forwards its callbacks onto ``LocationManagingDelegate``. It reaches back
/// to its owning ``LiveLocationManager`` through a closure so neither holds
/// the other strongly (avoiding a retain cycle with the manager's `delegate`).
private final class LocationManagerDelegateBridge: NSObject, CLLocationManagerDelegate {

    /// Provides the current forwarding delegate without retaining it.
    var forwardingDelegateProvider: () -> (any LocationManagingDelegate)? = { nil }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        forwardingDelegateProvider()?.locationManager(self, didChangeAuthorization: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        forwardingDelegateProvider()?.locationManager(self, didUpdateLocations: locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        forwardingDelegateProvider()?.locationManager(self, didFailWithError: error)
    }
}
