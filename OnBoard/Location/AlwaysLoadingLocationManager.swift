import Foundation
import CoreLocation

final class AlwaysLoadingLocationManager: LocationManager {
    let authorizationStatus: CLAuthorizationStatus = .authorizedAlways

    var locationDelegate: (any LocationManagerDelegate)?
    
    func requestWhenInUseAuthorization() {
        locationDelegate?.locationManager(self, didChangeAuthorization: .authorizedAlways)
    }
    
    func startUpdatingLocation() {
    }
    
    func stopUpdatingLocation() {
    }
}
