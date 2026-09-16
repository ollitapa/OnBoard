import Foundation
import CoreLocation

/// A delegate surface for ``LocationManager`` that mirrors the subset of
/// `CLLocationManagerDelegate` the app needs, retyped against the protocol so
/// a mock manager can drive a ``LocationAuthorization`` model without
/// CoreLocation.
///
/// Methods are `nonisolated` because `CLLocationManager` delivers its
/// callbacks on the main run loop; conformers route onto `@MainActor` with
/// `MainActor.assumeIsolated`.
protocol LocationManagerDelegate: AnyObject {
    func locationManager(_ manager: any LocationManager, didChangeAuthorization status: CLAuthorizationStatus)
    func locationManager(_ manager: any LocationManager, didUpdateLocations locations: [CLLocation])
    func locationManager(_ manager: any LocationManager, didFailWithError error: any Error)
}

/// A minimal abstraction over `CLLocationManager` so the authorization
/// lifecycle and coordinate updates can be driven from tests.
///
/// The live conformance forwards to a real `CLLocationManager`; a mock
/// conformance records calls and dispatches delegate callbacks on demand.
protocol LocationManager: AnyObject {

    /// The current authorization status.
    var authorizationStatus: CLAuthorizationStatus { get }

    /// The object receiving authorization and location callbacks.
    var locationDelegate: (any LocationManagerDelegate)? { get set }

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
/// ``LocationManagerDelegate`` by an internal `NSObject` helper that owns the
/// `CLLocationManager`'s `delegate`. `LiveLocationManager` itself is a plain
/// `final class` (not `NSObject`); it is the bridge's delegate via
/// ``LocationManagerBridgeDelegate``, reached through a `weak` reference.
final class LiveLocationManager: LocationManager {

    private let clmanager: CLLocationManager
    private let bridge: LocationManagerDelegateBridge

    init() {
        let clmanager = CLLocationManager()
        let bridge = LocationManagerDelegateBridge()
        clmanager.delegate = bridge
        self.clmanager = clmanager
        self.bridge = bridge
        self.bridge.manager = self
    }

    var authorizationStatus: CLAuthorizationStatus { clmanager.authorizationStatus }

    var locationDelegate: (any LocationManagerDelegate)? {
        get { bridge.bridgeDelegate }
        set { bridge.bridgeDelegate = newValue }
    }

    func requestWhenInUseAuthorization() {
        clmanager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        clmanager.startUpdatingLocation()
    }

    func stopUpdatingLocation() {
        clmanager.stopUpdatingLocation()
    }
}

/// The `NSObject` adapter that satisfies `CLLocationManagerDelegate` and
/// forwards its callbacks to its ``LocationManagerBridgeDelegate`` (the owning
/// ``LiveLocationManager``) via a `weak` reference, avoiding a retain cycle
/// with the `CLLocationManager`'s `delegate`.
fileprivate final class LocationManagerDelegateBridge: NSObject, CLLocationManagerDelegate {

    weak var manager: any LocationManager?

    /// The owning manager, held weakly to avoid a retain cycle with the
    /// `CLLocationManager`'s `delegate` (which retains this bridge).
    weak var bridgeDelegate: (any LocationManagerDelegate)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        bridgeDelegate?.locationManager(
            self.manager!,
            didChangeAuthorization: manager.authorizationStatus
        )
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        bridgeDelegate?.locationManager(
            self.manager!,
            didUpdateLocations: locations
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        bridgeDelegate?.locationManager(
            self.manager!,
            didFailWithError: error
        )
    }
}
