import CoreLocation
import Foundation
import Observation

/// How much to trust the current fix. Thresholds are tuned for the wrist: a watch
/// under a tree canopy routinely sits at 8–12 m, which is still fine for club choice.
enum GPSQuality: Int, Comparable, Sendable {
    case none = 0
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4

    static func < (lhs: GPSQuality, rhs: GPSQuality) -> Bool { lhs.rawValue < rhs.rawValue }

    init(horizontalAccuracy: Double) {
        switch horizontalAccuracy {
        case ..<0: self = .none
        case ..<5: self = .excellent
        case ..<10: self = .good
        case ..<20: self = .fair
        default: self = .poor
        }
    }

    var label: String {
        switch self {
        case .none: return "No fix"
        case .poor: return "Weak"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Strong"
        }
    }

    /// Below this the app warns before letting a shot be logged into the stats.
    var isUsableForShotLogging: Bool { self >= .fair }
}

/// Wraps CoreLocation for both platforms. On watchOS the app is only kept alive
/// during a round by `WorkoutManager`'s HKWorkoutSession — without it watchOS
/// suspends the app between holes and these updates stop arriving.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var currentLocation: GeoPoint?
    private(set) var horizontalAccuracy: Double = -1
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var isTracking = false
    /// Course over ground in degrees, used to orient the hole map. Negative when unknown.
    private(set) var course: Double = -1

    var quality: GPSQuality { GPSQuality(horizontalAccuracy: horizontalAccuracy) }

    var hasAuthorization: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Fires on every accepted fix, so the round engine can drop a breadcrumb.
    var onLocationUpdate: ((GeoPoint, Double, Date) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        // A golfer walks; anything finer just burns battery on noise.
        manager.distanceFilter = 3
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    /// Call when a round starts. Background updates need the `location` background
    /// mode, declared in both targets' Info.plist.
    func startTracking() {
        guard !isTracking else { return }
        guard hasAuthorization else {
            requestAuthorization()
            return
        }
        manager.allowsBackgroundLocationUpdates = true
        #if !os(watchOS)
        manager.pausesLocationUpdatesAutomatically = false
        #endif
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stopTracking() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if hasAuthorization, isTracking {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // A negative accuracy means the fix is invalid, not merely imprecise.
        guard location.horizontalAccuracy >= 0 else { return }
        // Stale cached fixes arrive first on a cold start; they are usually kilometres off.
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }

        let point = GeoPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        currentLocation = point
        horizontalAccuracy = location.horizontalAccuracy
        course = location.course
        onLocationUpdate?(point, location.horizontalAccuracy, location.timestamp)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure is normal walking between holes; only a permanent
        // denial matters, and that arrives through the authorization callback.
        if (error as? CLError)?.code == .denied {
            stopTracking()
        }
    }
}
