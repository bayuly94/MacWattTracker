import Foundation
import CoreLocation

public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()

    private let manager = CLLocationManager()

    @Published public var lastLocation: CLLocation? = nil
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isAuthorized: Bool = false
    @Published public var locationErrorMessage: String? = nil

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25.0
        self.authorizationStatus = manager.authorizationStatus
        self.isAuthorized = (manager.authorizationStatus == .authorizedAlways)
    }

    public func requestPermission() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    public func start() {
        manager.startUpdatingLocation()
    }

    public func stop() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.authorizationStatus = manager.authorizationStatus
            #if os(macOS)
            let authorized = (manager.authorizationStatus == .authorizedAlways)
            #else
            let authorized = (manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse)
            #endif
            self.isAuthorized = authorized

            if authorized {
                manager.startUpdatingLocation()
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastLocation = latest
            PowerMonitor.shared.handleGPSLocationUpdate(latest)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.locationErrorMessage = error.localizedDescription
        }
    }
}
