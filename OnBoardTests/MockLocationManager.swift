import Foundation
import CoreLocation
@testable import OnBoard

/// A mock `LocationManaging` for driving a ``LocationAuthorization`` model in
/// tests without CoreLocation.
///
/// Records the calls made against it and lets a test drive the delegate
/// callbacks (`didChangeAuthorization`, `didUpdateLocations`, `didFail`)
/// deterministically. Mirrors the recording style of `MockNetwork`.
final class MockLocationManager: LocationManaging {

    /// A request captured from `requestWhenInUseAuthorization`.
    struct AuthorizationRequest: Equatable {
        var whenInUseRequested: Bool
    }

    /// A request captured from `startUpdatingLocation`/`stopUpdatingLocation`.
    struct UpdatesRequest: Equatable {
        var started: Bool
    }

    /// The status the mock reports.
    var authorizationStatus: CLAuthorizationStatus

    /// The recorded authorization requests.
    private(set) var authorizationRequests: [AuthorizationRequest] = []

    /// The recorded update start/stop requests, in order.
    private(set) var updatesRequests: [UpdatesRequest] = []

    /// The delegate the mock forwards callbacks to.
    weak var delegate: (any LocationManagingDelegate)?

    /// Creates a mock reporting the given status (default `.notDetermined`).
    init(authorizationStatus: CLAuthorizationStatus = .notDetermined) {
        self.authorizationStatus = authorizationStatus
    }

    func requestWhenInUseAuthorization() {
        authorizationRequests.append(AuthorizationRequest(whenInUseRequested: true))
    }

    func startUpdatingLocation() {
        updatesRequests.append(UpdatesRequest(started: true))
    }

    func stopUpdatingLocation() {
        updatesRequests.append(UpdatesRequest(started: false))
    }

    // MARK: - Test-driven delegate callbacks

    /// Drives the `didChangeAuthorization` callback onto the delegate, updating
    /// the reported status so the model observes the new value.
    func simulateAuthorizationChange(_ status: CLAuthorizationStatus) {
        self.authorizationStatus = status
        delegate?.locationManager(self, didChangeAuthorization: status)
    }

    /// Drives the `didUpdateLocations` callback onto the delegate.
    func simulateLocations(_ locations: [CLLocation]) {
        delegate?.locationManager(self, didUpdateLocations: locations)
    }

    /// Drives the `didFailWithError` callback onto the delegate.
    func simulateFailure(_ error: some Error) {
        delegate?.locationManager(self, didFailWithError: error)
    }
}

/// A simple `Error` for simulating location failures in tests.
struct MockLocationError: Error, Equatable {
    var message: String
}
