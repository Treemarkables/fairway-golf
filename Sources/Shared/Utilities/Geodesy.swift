import Foundation

/// A plain latitude/longitude pair. Deliberately free of CoreLocation so the
/// geometry below stays unit-testable and identical on iOS and watchOS.
struct GeoPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Distances to the three reference points golfers actually aim at.
struct GreenDistances: Equatable, Sendable {
    /// Metres to the near edge of the green, along the line of play.
    var front: Double
    /// Metres to the centroid of the green.
    var center: Double
    /// Metres to the far edge of the green, along the line of play.
    var back: Double

    /// How deep the green plays from the player's current position.
    var depth: Double { max(0, back - front) }
}

enum Geodesy {
    /// IUGG mean earth radius, metres.
    static let earthRadius: Double = 6_371_008.8

    // MARK: - Spherical primitives

    /// Great-circle distance in metres (haversine).
    static func distance(from a: GeoPoint, to b: GeoPoint) -> Double {
        let lat1 = a.latitude.radians
        let lat2 = b.latitude.radians
        let dLat = (b.latitude - a.latitude).radians
        let dLon = (b.longitude - a.longitude).radians

        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    /// Initial bearing from `a` to `b`, degrees clockwise from true north, 0..<360.
    static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let lat1 = a.latitude.radians
        let lat2 = b.latitude.radians
        let dLon = (b.longitude - a.longitude).radians

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x).degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point reached by travelling `distance` metres along `bearing` from `origin`.
    static func destination(from origin: GeoPoint, bearing: Double, distance: Double) -> GeoPoint {
        let angular = distance / earthRadius
        let lat1 = origin.latitude.radians
        let lon1 = origin.longitude.radians
        let brg = bearing.radians

        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(brg))
        let lon2 = lon1 + atan2(
            sin(brg) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return GeoPoint(
            latitude: lat2.degrees,
            longitude: ((lon2.degrees + 540).truncatingRemainder(dividingBy: 360)) - 180
        )
    }

    /// Smallest signed difference between two bearings, degrees in -180...180.
    static func angleDifference(_ a: Double, _ b: Double) -> Double {
        var delta = (a - b).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    // MARK: - Polygon helpers

    /// Area-weighted centroid, computed in a local equirectangular projection.
    /// A green is ~30 m across so projection error is far below GPS noise.
    /// Degenerate (zero-area) rings fall back to the arithmetic mean.
    static func centroid(of polygon: [GeoPoint]) -> GeoPoint? {
        guard let first = polygon.first else { return nil }

        func mean(_ points: [GeoPoint]) -> GeoPoint {
            let lat = points.reduce(0) { $0 + $1.latitude } / Double(points.count)
            let lon = points.reduce(0) { $0 + $1.longitude } / Double(points.count)
            return GeoPoint(latitude: lat, longitude: lon)
        }

        guard polygon.count > 2 else { return mean(polygon) }

        let metresPerDegreeLatitude = 111_132.0
        let metresPerDegreeLongitude = 111_320.0 * cos(first.latitude.radians)

        // Guard against a course mapped at the poles, where the longitude scale collapses.
        guard abs(metresPerDegreeLongitude) > 1 else { return mean(polygon) }

        func project(_ p: GeoPoint) -> (x: Double, y: Double) {
            ((p.longitude - first.longitude) * metresPerDegreeLongitude,
             (p.latitude - first.latitude) * metresPerDegreeLatitude)
        }

        var ring = polygon
        // OSM ways repeat the first vertex to close the ring; drop it.
        if ring.count > 3, ring.first == ring.last { ring.removeLast() }
        guard ring.count > 2 else { return mean(ring) }

        var twiceArea = 0.0
        var accumulatedX = 0.0
        var accumulatedY = 0.0
        for index in ring.indices {
            let p0 = project(ring[index])
            let p1 = project(ring[(index + 1) % ring.count])
            let cross = p0.x * p1.y - p1.x * p0.y
            twiceArea += cross
            accumulatedX += (p0.x + p1.x) * cross
            accumulatedY += (p0.y + p1.y) * cross
        }

        guard abs(twiceArea) > 1e-9 else { return mean(ring) }

        let area = twiceArea / 2
        let x = accumulatedX / (6 * area)
        let y = accumulatedY / (6 * area)
        return GeoPoint(
            latitude: first.latitude + y / metresPerDegreeLatitude,
            longitude: first.longitude + x / metresPerDegreeLongitude
        )
    }

    /// Front / centre / back distances to a green, measured **along the line of play**
    /// rather than as raw nearest/farthest distance to the outline.
    ///
    /// Each vertex is projected onto the player→centre axis, so a green lying side-on
    /// still reports the depth the player actually has to work with. A single-point
    /// "green" (a manually dropped pin) returns the same value three times.
    static func greenDistances(from player: GeoPoint, green: [GeoPoint]) -> GreenDistances? {
        guard let centre = centroid(of: green) else { return nil }
        let centreDistance = distance(from: player, to: centre)

        guard green.count > 1 else {
            return GreenDistances(front: centreDistance, center: centreDistance, back: centreDistance)
        }

        // Standing on the centroid there is no meaningful line of play.
        guard centreDistance > 0.5 else {
            let spread = green.map { distance(from: centre, to: $0) }.max() ?? 0
            return GreenDistances(front: 0, center: 0, back: spread)
        }

        let axis = bearing(from: player, to: centre)
        var nearest = Double.greatestFiniteMagnitude
        var farthest = -Double.greatestFiniteMagnitude

        for vertex in green {
            let d = distance(from: player, to: vertex)
            let theta = angleDifference(bearing(from: player, to: vertex), axis).radians
            let projection = d * cos(theta)
            nearest = min(nearest, projection)
            farthest = max(farthest, projection)
        }

        return GreenDistances(
            front: max(0, nearest),
            center: centreDistance,
            back: max(0, farthest)
        )
    }

    /// Ray-casting point-in-polygon test — used to decide whether a shot finished on the green.
    static func contains(_ point: GeoPoint, polygon: [GeoPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.latitude > point.latitude) != (pj.latitude > point.latitude) {
                let slope = (pj.longitude - pi.longitude) / (pj.latitude - pi.latitude)
                let intersect = pi.longitude + (point.latitude - pi.latitude) * slope
                if point.longitude < intersect { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
