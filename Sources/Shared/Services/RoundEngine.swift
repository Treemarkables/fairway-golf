import Foundation
import Observation

/// Drives a round in progress. Deliberately knows nothing about CoreLocation or SwiftUI —
/// it takes plain `GeoPoint`s — so the identical logic runs on the phone and the watch
/// and is straightforward to unit test.
///
/// The shot model is "origin now, end later": logging a shot records where you struck it
/// from, and the *next* logged shot (or closing out the hole) supplies where it finished.
/// That is what turns a tap on the watch into a measured distance.
@Observable
final class RoundEngine {

    private(set) var round: Round?
    private(set) var course: Course?
    private(set) var currentHoleNumber: Int = 1

    /// Called whenever the round mutates, so it can be persisted and mirrored to the
    /// other device. Kept as a closure to avoid wiring storage into the engine.
    @ObservationIgnored var onChange: ((Round) -> Void)?

    var isActive: Bool { round != nil && round?.finishedAt == nil }

    var currentHole: Hole? { course?.hole(number: currentHoleNumber) }

    var currentHoleScore: HoleScore? { round?.holeScore(number: currentHoleNumber) }

    /// The shot awaiting an endpoint — i.e. the ball is in the air or on the ground
    /// somewhere ahead of you.
    var openShot: Shot? {
        currentHoleScore?.shots.last(where: { !$0.isClosed })
    }

    var holeNumbers: [Int] { course?.holes.map(\.number).sorted() ?? [] }

    // MARK: - Lifecycle

    func start(course: Course, at date: Date = Date()) {
        self.course = course
        let holes = course.holes
            .sorted { $0.number < $1.number }
            .map { HoleScore(holeNumber: $0.number, par: $0.par) }

        round = Round(
            courseID: course.id,
            courseName: course.name,
            startedAt: date,
            holes: holes
        )
        currentHoleNumber = course.holes.map(\.number).min() ?? 1
        commit()
    }

    /// Restores a round recovered from disk — after a crash, or when the watch picks up
    /// a round the phone already started.
    func resume(round: Round, course: Course) {
        self.round = round
        self.course = course
        // Drop the player back on the last hole they actually played.
        currentHoleNumber = round.playedHoles.map(\.holeNumber).max()
            ?? course.holes.map(\.number).min()
            ?? 1
    }

    @discardableResult
    func finish(at date: Date = Date(), location: GeoPoint? = nil, accuracy: Double = 0) -> Round? {
        guard var current = round else { return nil }
        if let location {
            closeOpenShot(in: &current, at: location, accuracy: accuracy)
        }
        current.finishedAt = date
        round = current
        commit()
        return current
    }

    func discard() {
        round = nil
        course = nil
        currentHoleNumber = 1
    }

    // MARK: - Shots

    /// Records a stroke struck from `point` with `club`, closing out the previous shot.
    func logShot(club: Club?, at point: GeoPoint, accuracy: Double, date: Date = Date()) {
        guard var current = round, current.finishedAt == nil else { return }
        closeOpenShot(in: &current, at: point, accuracy: accuracy)

        guard let index = current.holes.firstIndex(where: { $0.holeNumber == currentHoleNumber }) else { return }
        current.holes[index].shots.append(
            Shot(
                holeNumber: currentHoleNumber,
                clubID: club?.id,
                origin: point,
                struckAt: date,
                originAccuracy: accuracy
            )
        )

        // Putts are the one thing GPS can't measure, so logging one just counts it.
        if club?.kind == .putter {
            current.holes[index].putts += 1
        }

        round = current
        commit()
    }

    /// Removes the most recent shot on the current hole and reopens the one before it,
    /// so a mis-tap on the watch doesn't poison the club stats.
    func undoLastShot() {
        guard var current = round,
              let index = current.holes.firstIndex(where: { $0.holeNumber == currentHoleNumber }),
              let removed = current.holes[index].shots.popLast()
        else { return }

        if let clubID = removed.clubID,
           let club = bagLookup?(clubID),
           club.kind == .putter {
            current.holes[index].putts = max(0, current.holes[index].putts - 1)
        }

        // The previous shot's endpoint was this shot's origin — it is now unknown again.
        if !current.holes[index].shots.isEmpty {
            let last = current.holes[index].shots.count - 1
            current.holes[index].shots[last].end = nil
            current.holes[index].shots[last].endAccuracy = nil
        }

        round = current
        commit()
    }

    /// Resolves a club ID, so undo can tell a putt from a full shot. Injected by the
    /// app model rather than the engine owning the bag.
    @ObservationIgnored var bagLookup: ((UUID) -> Club?)?

    /// A stroke that isn't a swing: a penalty drop, or a stroke you forgot to log.
    func addPenaltyStroke() {
        guard var current = round,
              let index = current.holes.firstIndex(where: { $0.holeNumber == currentHoleNumber })
        else { return }
        current.holes[index].adjustment += 1
        round = current
        commit()
    }

    func setAdjustment(_ value: Int) {
        guard var current = round,
              let index = current.holes.firstIndex(where: { $0.holeNumber == currentHoleNumber })
        else { return }
        current.holes[index].adjustment = max(0, value)
        round = current
        commit()
    }

    func setPutts(_ value: Int) {
        guard var current = round,
              let index = current.holes.firstIndex(where: { $0.holeNumber == currentHoleNumber })
        else { return }
        current.holes[index].putts = max(0, value)
        round = current
        commit()
    }

    // MARK: - Navigation

    /// Moves to another hole, closing out the open shot at the player's current position.
    /// Called as you walk off the green, which is why that position is a fair endpoint.
    func moveToHole(_ number: Int, closingAt point: GeoPoint?, accuracy: Double = 0) {
        guard holeNumbers.contains(number) else { return }
        if let point, var current = round {
            closeOpenShot(in: &current, at: point, accuracy: accuracy)
            round = current
            commit()
        }
        currentHoleNumber = number
    }

    func nextHole(closingAt point: GeoPoint?, accuracy: Double = 0) {
        guard let next = holeNumbers.first(where: { $0 > currentHoleNumber }) else { return }
        moveToHole(next, closingAt: point, accuracy: accuracy)
    }

    func previousHole() {
        guard let previous = holeNumbers.last(where: { $0 < currentHoleNumber }) else { return }
        // Deliberately does not close a shot — going back is a correction, not progress.
        currentHoleNumber = previous
    }

    // MARK: - Distances

    /// Front / centre / back to the current hole's green from `point`.
    /// `nil` when the hole has no green marked yet.
    func distances(from point: GeoPoint) -> GreenDistances? {
        guard let green = currentHole?.green, !green.isEmpty else { return nil }
        return Geodesy.greenDistances(from: point, green: green.polygon)
    }

    // MARK: - Tracking

    /// Drops a breadcrumb. Sampled rather than stored on every fix — a 4-hour round at
    /// one fix per second would be 15,000 points for no benefit.
    func recordTrackPoint(_ point: GeoPoint, accuracy: Double, at date: Date = Date()) {
        guard var current = round, current.finishedAt == nil else { return }
        if let last = current.track.last {
            guard date.timeIntervalSince(last.timestamp) >= 10 else { return }
        }
        current.track.append(TrackPoint(point: point, timestamp: date, accuracy: accuracy))
        round = current
        // Deliberately no commit(): breadcrumbs are cheap to lose and committing on
        // every one would write the whole round to disk hundreds of times per round.
    }

    // MARK: - Internals

    private func closeOpenShot(in round: inout Round, at point: GeoPoint, accuracy: Double) {
        guard let holeIndex = round.holes.firstIndex(where: { $0.holeNumber == currentHoleNumber }),
              let shotIndex = round.holes[holeIndex].shots.lastIndex(where: { !$0.isClosed })
        else { return }
        round.holes[holeIndex].shots[shotIndex].end = point
        round.holes[holeIndex].shots[shotIndex].endAccuracy = accuracy
    }

    private func commit() {
        guard let round else { return }
        onChange?(round)
    }
}
