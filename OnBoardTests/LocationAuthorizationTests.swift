import Testing
import Foundation
import CoreLocation
@testable import OnBoard

@MainActor
struct LocationAuthorizationTests {

    // MARK: - Initial status

    @Test func initialStateNotDetermined() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .notDetermined)

        // When
        let model = LocationAuthorization(manager: manager)

        // Then
        #expect(model.status == .notDetermined)
        #expect(model.coordinate == nil)
        #expect(model.failure == nil)
    }

    @Test func initialStateReflectsGrantedStatus() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .authorizedWhenInUse)

        // When
        let model = LocationAuthorization(manager: manager)

        // Then
        #expect(model.status == .authorizedWhenInUse)
    }

    @Test func initialStateReflectsDeniedStatus() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .denied)

        // When
        let model = LocationAuthorization(manager: manager)

        // Then
        #expect(model.status == .denied)
    }

    // MARK: - Requesting authorization

    @Test func requestAuthorizationAsksSystemForWhenInUse() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .notDetermined)
        let model = LocationAuthorization(manager: manager)

        // When
        model.requestAuthorization()

        // Then
        #expect(manager.authorizationRequests == [.init(whenInUseRequested: true)])
    }

    @Test func grantingAuthorizationStartsLocationUpdates() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .notDetermined)
        let model = LocationAuthorization(manager: manager)

        // When: the system reports the user granted "when in use".
        manager.simulateAuthorizationChange(.authorizedWhenInUse)

        // Then: status reflects the grant and updates are started.
        #expect(model.status == .authorizedWhenInUse)
        #expect(manager.updatesRequests == [.init(started: true)])
    }

    @Test func denyingAuthorizationDoesNotStartUpdates() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .notDetermined)
        let model = LocationAuthorization(manager: manager)

        // When
        manager.simulateAuthorizationChange(.denied)

        // Then
        #expect(model.status == .denied)
        #expect(manager.updatesRequests == [])
    }

    // MARK: - startUpdating is gated on authorization

    @Test func startUpdatingBeforeAuthorizationIsNoOp() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .notDetermined)
        let model = LocationAuthorization(manager: manager)

        // When
        model.startUpdating()

        // Then
        #expect(manager.updatesRequests == [])
    }

    @Test func startUpdatingAfterAuthorizationBeginsUpdates() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .authorizedAlways)
        let model = LocationAuthorization(manager: manager)

        // When
        model.startUpdating()

        // Then
        #expect(manager.updatesRequests == [.init(started: true)])
    }

    @Test func stopUpdatingRequestsStop() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .authorizedWhenInUse)
        let model = LocationAuthorization(manager: manager)

        // When
        model.stopUpdating()

        // Then
        #expect(manager.updatesRequests == [.init(started: false)])
    }

    // MARK: - Coordinate updates

    @Test func locationUpdatesPublishLastCoordinate() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .authorizedWhenInUse)
        let model = LocationAuthorization(manager: manager)
        let locations = [
            CLLocation(latitude: 59.31, longitude: 18.07),
            CLLocation(latitude: 59.32, longitude: 18.08)
        ]

        // When
        manager.simulateLocations(locations)

        // Then
        let coordinate = try #require(model.coordinate)
        #expect(coordinate.latitude == 59.32)
        #expect(coordinate.longitude == 18.08)
        #expect(model.failure == nil)
    }

    @Test func locationUpdatesOverwritePreviousCoordinate() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .authorizedWhenInUse)
        let model = LocationAuthorization(manager: manager)

        // When
        manager.simulateLocations([CLLocation(latitude: 59.31, longitude: 18.07)])
        manager.simulateLocations([CLLocation(latitude: 60.17, longitude: 24.94)])

        // Then
        let coordinate = try #require(model.coordinate)
        #expect(coordinate.latitude == 60.17)
        #expect(coordinate.longitude == 24.94)
    }

    // MARK: - Failure handling

    @Test func failureCallbackSurfacesErrorMessage() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .authorizedWhenInUse)
        let model = LocationAuthorization(manager: manager)

        // When
        manager.simulateFailure(MockLocationError(message: "no fix"))

        // Then
        #expect(model.failure != nil)
        #expect(model.failure?.contains("no fix") == true)
    }

    @Test func successfulLocationClearsPreviousFailure() {
        // Given
        let manager = MockLocationManager(authorizationStatus: .authorizedWhenInUse)
        let model = LocationAuthorization(manager: manager)
        manager.simulateFailure(MockLocationError(message: "no fix"))
        #expect(model.failure != nil)

        // When
        manager.simulateLocations([CLLocation(latitude: 59.31, longitude: 18.07)])

        // Then
        #expect(model.failure == nil)
    }

    // MARK: - Status transitions

    @Test func reEnablingInSettingsRestartsUpdates() {
        // Given: a model that started denied.
        let manager = MockLocationManager(authorizationStatus: .denied)
        let model = LocationAuthorization(manager: manager)
        #expect(model.status == .denied)

        // When: the user re-enables location in Settings.
        manager.simulateAuthorizationChange(.authorizedWhenInUse)

        // Then: status and updates reflect the re-grant.
        #expect(model.status == .authorizedWhenInUse)
        #expect(manager.updatesRequests == [.init(started: true)])
    }
}
