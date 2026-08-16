import Foundation

/// Where a course's geometry came from. Manual edits always win over a re-import.
enum CourseSource: String, Codable, Sendable {
    case manual
    case openStreetMap

    var displayName: String {
        switch self {
        case .manual: return "Marked by hand"
        case .openStreetMap: return "OpenStreetMap"
        }
    }
}

/// A green outline. One point is a legitimate degenerate case: a pin dropped by
/// hand, which yields identical front/centre/back distances.
struct Green: Codable, Hashable, Sendable {
    var polygon: [GeoPoint]

    init(polygon: [GeoPoint]) {
        self.polygon = polygon
    }

    init(pin: GeoPoint) {
        self.polygon = [pin]
    }

    var center: GeoPoint? { Geodesy.centroid(of: polygon) }
    var isPinOnly: Bool { polygon.count == 1 }
    var isEmpty: Bool { polygon.isEmpty }
}

struct TeeBox: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// "Blue", "White", "Yellow" — free text, courses name these inconsistently.
    var name: String
    var point: GeoPoint

    init(id: UUID = UUID(), name: String, point: GeoPoint) {
        self.id = id
        self.name = name
        self.point = point
    }
}

struct Hole: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var number: Int
    var par: Int
    /// Stroke index / handicap rating. Optional — OSM data often omits it.
    var strokeIndex: Int?
    var green: Green?
    var tees: [TeeBox]

    init(
        id: UUID = UUID(),
        number: Int,
        par: Int = 4,
        strokeIndex: Int? = nil,
        green: Green? = nil,
        tees: [TeeBox] = []
    ) {
        self.id = id
        self.number = number
        self.par = par
        self.strokeIndex = strokeIndex
        self.green = green
        self.tees = tees
    }

    /// True if this hole can drive a distance readout.
    var hasGreen: Bool {
        guard let green else { return false }
        return !green.isEmpty
    }

    /// Nominal tee-to-green length in metres, from the first tee box on file.
    var nominalLength: Double? {
        guard let tee = tees.first, let centre = green?.center else { return nil }
        return Geodesy.distance(from: tee.point, to: centre)
    }
}

struct Course: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Town or region, to tell apart the several "Riverside Golf Club"s.
    var locality: String?
    var holes: [Hole]
    var source: CourseSource
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        locality: String? = nil,
        holes: [Hole] = [],
        source: CourseSource = .manual,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.locality = locality
        self.holes = holes.sorted { $0.number < $1.number }
        self.source = source
        self.updatedAt = updatedAt
    }

    func hole(number: Int) -> Hole? {
        holes.first { $0.number == number }
    }

    var par: Int { holes.reduce(0) { $0 + $1.par } }

    /// How much of the course is actually usable for distance readouts.
    var mappedHoleCount: Int { holes.filter(\.hasGreen).count }

    var isFullyMapped: Bool { !holes.isEmpty && mappedHoleCount == holes.count }

    /// A blank 18 holes, all par 4, ready for greens to be marked by hand.
    static func blank(name: String, holeCount: Int = 18) -> Course {
        Course(
            name: name,
            holes: (1...max(1, holeCount)).map { Hole(number: $0) },
            source: .manual
        )
    }
}
