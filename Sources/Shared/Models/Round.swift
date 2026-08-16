import Foundation

/// One stroke. `origin` is where the ball was struck from; `end` is filled in when the
/// next shot is logged or the hole is closed out, which is what makes the distance real.
struct Shot: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var holeNumber: Int
    var clubID: UUID?
    var origin: GeoPoint
    var end: GeoPoint?
    var struckAt: Date
    /// Horizontal accuracy of the fix at `origin`, metres. Used to discard junk from stats.
    var originAccuracy: Double
    /// Horizontal accuracy of the fix at `end`, metres.
    var endAccuracy: Double?
    /// Penalty strokes count on the card but never in club distance stats.
    var isPenalty: Bool

    init(
        id: UUID = UUID(),
        holeNumber: Int,
        clubID: UUID?,
        origin: GeoPoint,
        end: GeoPoint? = nil,
        struckAt: Date = Date(),
        originAccuracy: Double = 0,
        endAccuracy: Double? = nil,
        isPenalty: Bool = false
    ) {
        self.id = id
        self.holeNumber = holeNumber
        self.clubID = clubID
        self.origin = origin
        self.end = end
        self.struckAt = struckAt
        self.originAccuracy = originAccuracy
        self.endAccuracy = endAccuracy
        self.isPenalty = isPenalty
    }

    /// Measured ground distance in metres, once the shot has been closed out.
    /// This is **total** distance — where the ball came to rest, roll included —
    /// not carry. See `ClubStatsEngine` for why that distinction matters.
    var measuredDistance: Double? {
        guard let end else { return nil }
        return Geodesy.distance(from: origin, to: end)
    }

    var isClosed: Bool { end != nil }

    /// The worse of the two fixes bounding this shot.
    var worstAccuracy: Double {
        max(originAccuracy, endAccuracy ?? originAccuracy)
    }
}

struct HoleScore: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var holeNumber: Int
    var par: Int
    var shots: [Shot]
    /// Putts, entered by hand — GPS can't infer them reliably.
    var putts: Int
    /// Extra strokes not tied to a logged shot (penalties, unrecorded strokes).
    var adjustment: Int

    init(
        id: UUID = UUID(),
        holeNumber: Int,
        par: Int,
        shots: [Shot] = [],
        putts: Int = 0,
        adjustment: Int = 0
    ) {
        self.id = id
        self.holeNumber = holeNumber
        self.par = par
        self.shots = shots
        self.putts = putts
        self.adjustment = adjustment
    }

    var strokes: Int { shots.count + adjustment }
    var scoreToPar: Int { strokes - par }
    var isPlayed: Bool { strokes > 0 }
}

/// A GPS breadcrumb, sampled through the round. Feeds the map trace and lets a
/// mis-logged shot be repaired after the fact.
struct TrackPoint: Codable, Hashable, Sendable {
    var point: GeoPoint
    var timestamp: Date
    var accuracy: Double
}

struct Round: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var courseID: UUID
    /// Denormalised so history still reads correctly if the course is later deleted.
    var courseName: String
    var startedAt: Date
    var finishedAt: Date?
    var holes: [HoleScore]
    var track: [TrackPoint]

    init(
        id: UUID = UUID(),
        courseID: UUID,
        courseName: String,
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        holes: [HoleScore] = [],
        track: [TrackPoint] = []
    ) {
        self.id = id
        self.courseID = courseID
        self.courseName = courseName
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.holes = holes
        self.track = track
    }

    var isComplete: Bool { finishedAt != nil }

    var playedHoles: [HoleScore] { holes.filter(\.isPlayed) }

    var totalStrokes: Int { holes.reduce(0) { $0 + $1.strokes } }

    var totalPutts: Int { holes.reduce(0) { $0 + $1.putts } }

    /// Par for the holes actually played, so a walked-off nine still scores sensibly.
    var parForPlayedHoles: Int { playedHoles.reduce(0) { $0 + $1.par } }

    var scoreToPar: Int { totalStrokes - parForPlayedHoles }

    var allShots: [Shot] { holes.flatMap(\.shots) }

    func holeScore(number: Int) -> HoleScore? {
        holes.first { $0.holeNumber == number }
    }

    /// "+4", "E", "-2" — the way a card is actually read.
    var scoreToParDisplay: String {
        let value = scoreToPar
        if value == 0 { return "E" }
        return value > 0 ? "+\(value)" : "\(value)"
    }
}
