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

/// Delegate of ``LocationManagerDelegateBridge``: receives the CoreLocation
/// events the bridge forwards, re-typed against the owning ``LocationManaging``.
/// `LiveLocationManager` conforms to this so the bridge can hand callbacks
/// back to it via a simple `weak` reference instead of closures.
private protocol LocationManagerBridgeDelegate: AnyObject {
    func bridge(_ bridge: LocationManagerDelegateBridge, didChangeAuthorization status: CLAuthorizationStatus)
    func bridge(_ bridge: LocationManagerDelegateBridge, didUpdateLocations locations: [CLLocation])
    func bridge(_ bridge: LocationManagerDelegateBridge, didFailWithError error: any Error)
}

/// Live conformance that forwards every call to a real `CLLocationManager`.
///
/// `CLLocationManagerDelegate` callbacks are bridged onto
/// ``LocationManagingDelegate`` by an internal `NSObject` helper that owns the
/// `CLLocationManager`'s `delegate`. `LiveLocationManager` itself is a plain
/// `final class` (not `NSObject`); it is the bridge's delegate via
/// ``LocationManagerBridgeDelegate``, reached through a `weak` reference.
final class LiveLocationManager: LocationManaging, LocationManagerBridgeDelegate {

    private let manager: CLLocationManager
    private let bridge: LocationManagerDelegateBridge
    private weak var forwardingDelegate: (any LocationManagingDelegate)?

    init() {
        let manager = CLLocationManager()
        let bridge = LocationManagerDelegateBridge()
        manager.delegate = bridge
        self.manager = manager
        self.bridge = bridge
        bridge.bridgeDelegate = self
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

    // MARK: LocationManagerBridgeDelegate

    func bridge(_ bridge: LocationManagerDelegateBridge, didChangeAuthorization status: CLAuthorizationStatus) {
        forwardingDelegate?.locationManager(self, didChangeAuthorization: status)
    }

    func bridge(_ bridge: LocationManagerDelegateBridge, didUpdateLocations locations: [CLLocation]) {
        forwardingDelegate?.locationManager(self, didUpdateLocations: locations)
    }

    func bridge(_ bridge: LocationManagerDelegateBridge, didFailWithError error: any Error) {
        forwardingDelegate?.locationManager(self, didFailWithError: error)
    }
}

/// The `NSObject` adapter that satisfies `CLLocationManagerDelegate` and
/// forwards its callbacks to its ``LocationManagerBridgeDelegate`` (the owning
/// ``LiveLocationManager``) via a `weak` reference, avoiding a retain cycle
/// with the `CLLocationManager`'s `delegate`.
private final class LocationManagerDelegateBridge: NSObject, CLLocationManagerDelegate {

    /// The owning manager, held weakly to avoid a retain cycle with the
    /// `CLLocationManager`'s `delegate` (which retains this bridge).
    weak var bridgeDelegate: (any LocationManagerBridgeDelegate)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        bridgeDelegate?.bridge(self, didChangeAuthorization: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        bridgeDelegate?.bridge(self, didUpdateLocations: locations)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        bridgeDelegate?.bridge(self, didFailWithError: error)
    }
}
