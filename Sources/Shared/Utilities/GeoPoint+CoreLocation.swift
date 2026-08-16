import CoreLocation
import Foundation

extension GeoPoint {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension Array where Element == GeoPoint {
    var coordinates: [CLLocationCoordinate2D] { map(\.coordinate) }
}
