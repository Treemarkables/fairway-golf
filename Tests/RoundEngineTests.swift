import XCTest

final class RoundEngineTests: XCTestCase {

    private let tee = GeoPoint(latitude: -36.8509, longitude: 174.7645)

    private func course(holeCount: Int = 3) -> Course {
        let holes = (1...holeCount).map { number -> Hole in
            let teePoint = Geodesy.destination(from: tee, bearing: 90, distance: Double(number) * 500)
            let greenCentre = Geodesy.destination(from: teePoint, bearing: 0, distance: 350)
            let green = Green(
                polygon: [0.0, 90.0, 180.0, 270.0].map {
                    Geodesy.destination(from: greenCentre, bearing: $0, distance: 15)
                }
            )
            return Hole(
                number: number,
                par: 4,
                green: green,
                tees: [TeeBox(name: "Tee", point: teePoint)]
            )
        }
        return Course(name: "Test Links", holes: holes)
    }

    private func startedEngine() -> (RoundEngine, Course) {
        let engine = RoundEngine()
        let course = course()
        engine.start(course: course)
        return (engine, course)
    }

    // MARK: - Lifecycle

    func testStartingARoundCreatesAScorecardForEveryHole() {
        let (engine, course) = startedEngine()

        XCTAssertTrue(engine.isActive)
        XCTAssertEqual(engine.round?.holes.count, course.holes.count)
        XCTAssertEqual(engine.currentHoleNumber, 1)
        XCTAssertEqual(engine.round?.totalStrokes, 0)
    }

    func testOnChangeFiresForEveryMutation() {
        let engine = RoundEngine()
        var notifications = 0
        engine.onChange = { _ in notifications += 1 }

        engine.start(course: course())
        engine.logShot(club: Bag.standard.inBag[0], at: tee, accuracy: 5)

        XCTAssertEqual(notifications, 2)
    }

    func testFinishingStampsTheRoundAndClosesTheLastShot() throws {
        let (engine, _) = startedEngine()
        let driver = Bag.standard.club(withID: Bag.standard.inBag[0].id)

        engine.logShot(club: driver, at: tee, accuracy: 5)
        let restingPlace = Geodesy.destination(from: tee, bearing: 0, distance: 210)
        let finished = try XCTUnwrap(engine.finish(location: restingPlace, accuracy: 5))

        XCTAssertNotNil(finished.finishedAt)
        XCTAssertTrue(finished.isComplete)
        let shot = try XCTUnwrap(finished.allShots.first)
        XCTAssertEqual(try XCTUnwrap(shot.measuredDistance), 210, accuracy: 1.0)
    }

    // MARK: - Shot chaining

    /// The core of the whole app: a shot's distance comes from where the *next* shot
    /// was struck, so logging two shots measures the first one.
    func testLoggingASecondShotClosesOutTheFirst() throws {
        let (engine, _) = startedEngine()
        let driver = Bag.standard.inBag[0]
        let iron = Bag.standard.inBag[6]

        engine.logShot(club: driver, at: tee, accuracy: 4)
        let ballPosition = Geodesy.destination(from: tee, bearing: 0, distance: 225)
        engine.logShot(club: iron, at: ballPosition, accuracy: 4)

        let shots = try XCTUnwrap(engine.currentHoleScore?.shots)
        XCTAssertEqual(shots.count, 2)
        XCTAssertEqual(try XCTUnwrap(shots[0].measuredDistance), 225, accuracy: 1.0)
        XCTAssertTrue(shots[0].isClosed)
        XCTAssertFalse(shots[1].isClosed, "the shot just struck has nowhere to land yet")
        XCTAssertEqual(engine.openShot?.id, shots[1].id)
    }

    func testUndoRemovesTheLastShotAndReopensThePreviousOne() throws {
        let (engine, _) = startedEngine()
        engine.bagLookup = { id in Bag.standard.club(withID: id) }

        engine.logShot(club: Bag.standard.inBag[0], at: tee, accuracy: 4)
        engine.logShot(
            club: Bag.standard.inBag[6],
            at: Geodesy.destination(from: tee, bearing: 0, distance: 225),
            accuracy: 4
        )
        engine.undoLastShot()

        let shots = try XCTUnwrap(engine.currentHoleScore?.shots)
        XCTAssertEqual(shots.count, 1)
        XCTAssertFalse(shots[0].isClosed, "undo must reopen the shot it had closed")
        XCTAssertNil(shots[0].measuredDistance)
    }

    func testUndoingAPuttDecrementsThePuttCount() throws {
        let (engine, _) = startedEngine()
        engine.bagLookup = { id in Bag.standard.club(withID: id) }
        let putter = try XCTUnwrap(Bag.standard.clubs.first { $0.kind == .putter })

        engine.logShot(club: putter, at: tee, accuracy: 5)
        XCTAssertEqual(engine.currentHoleScore?.putts, 1)

        engine.undoLastShot()
        XCTAssertEqual(engine.currentHoleScore?.putts, 0)
    }

    func testUndoOnAnEmptyHoleIsHarmless() {
        let (engine, _) = startedEngine()
        engine.undoLastShot()
        XCTAssertEqual(engine.round?.totalStrokes, 0)
    }

    // MARK: - Navigation

    func testMovingToTheNextHoleClosesTheOpenShot() throws {
        let (engine, _) = startedEngine()
        engine.logShot(club: Bag.standard.inBag[0], at: tee, accuracy: 4)

        let green = Geodesy.destination(from: tee, bearing: 0, distance: 180)
        engine.nextHole(closingAt: green, accuracy: 4)

        XCTAssertEqual(engine.currentHoleNumber, 2)
        let firstHole = try XCTUnwrap(engine.round?.holeScore(number: 1))
        XCTAssertEqual(try XCTUnwrap(firstHole.shots[0].measuredDistance), 180, accuracy: 1.0)
    }

    /// Going back is a correction, so it must not invent an endpoint for a live shot.
    func testGoingBackAHoleDoesNotCloseAnything() throws {
        let (engine, _) = startedEngine()
        engine.nextHole(closingAt: nil)
        engine.logShot(club: Bag.standard.inBag[0], at: tee, accuracy: 4)
        engine.previousHole()

        XCTAssertEqual(engine.currentHoleNumber, 1)
        let second = try XCTUnwrap(engine.round?.holeScore(number: 2))
        XCTAssertFalse(second.shots[0].isClosed)
    }

    func testNavigationStopsAtTheEndsOfTheCourse() {
        let (engine, _) = startedEngine()

        engine.previousHole()
        XCTAssertEqual(engine.currentHoleNumber, 1)

        for _ in 0..<10 { engine.nextHole(closingAt: nil) }
        XCTAssertEqual(engine.currentHoleNumber, 3)
    }

    // MARK: - Scoring

    func testPenaltyStrokesCountOnTheCardButCarryNoShot() throws {
        let (engine, _) = startedEngine()
        engine.logShot(club: Bag.standard.inBag[0], at: tee, accuracy: 4)
        engine.addPenaltyStroke()

        let hole = try XCTUnwrap(engine.currentHoleScore)
        XCTAssertEqual(hole.strokes, 2)
        XCTAssertEqual(hole.shots.count, 1)
    }

    func testScoreToParUsesOnlyThePlayedHoles() throws {
        let (engine, _) = startedEngine()
        // Five strokes on a par 4, then walk in.
        for _ in 0..<5 {
            engine.logShot(club: Bag.standard.inBag[6], at: tee, accuracy: 4)
        }
        let round = try XCTUnwrap(engine.round)

        XCTAssertEqual(round.playedHoles.count, 1)
        XCTAssertEqual(round.parForPlayedHoles, 4)
        XCTAssertEqual(round.scoreToPar, 1)
        XCTAssertEqual(round.scoreToParDisplay, "+1")
    }

    // MARK: - Distances

    func testDistancesComeFromTheCurrentHolesGreen() throws {
        let (engine, course) = startedEngine()
        let firstTee = try XCTUnwrap(course.holes[0].tees.first?.point)

        let onHoleOne = try XCTUnwrap(engine.distances(from: firstTee))
        XCTAssertEqual(onHoleOne.center, 350, accuracy: 1.0)

        engine.nextHole(closingAt: nil)
        let stillMeasuringFromHoleOnesTee = try XCTUnwrap(engine.distances(from: firstTee))
        XCTAssertGreaterThan(
            stillMeasuringFromHoleOnesTee.center,
            onHoleOne.center,
            "hole 2's green is further away from hole 1's tee"
        )
    }

    func testDistancesAreNilWhenTheHoleHasNoGreenMarked() {
        let engine = RoundEngine()
        engine.start(course: Course.blank(name: "Unmapped", holeCount: 3))
        XCTAssertNil(engine.distances(from: tee))
    }

    // MARK: - Recovery

    func testResumingPutsThePlayerBackOnTheLastPlayedHole() throws {
        let (engine, course) = startedEngine()
        engine.nextHole(closingAt: nil)
        engine.logShot(club: Bag.standard.inBag[0], at: tee, accuracy: 4)
        let saved = try XCTUnwrap(engine.round)

        let recovered = RoundEngine()
        recovered.resume(round: saved, course: course)

        XCTAssertEqual(recovered.currentHoleNumber, 2)
        XCTAssertTrue(recovered.isActive)
    }

    // MARK: - Breadcrumbs

    func testTrackPointsAreThrottled() throws {
        let (engine, _) = startedEngine()
        let start = Date()

        engine.recordTrackPoint(tee, accuracy: 5, at: start)
        engine.recordTrackPoint(tee, accuracy: 5, at: start.addingTimeInterval(2))
        engine.recordTrackPoint(tee, accuracy: 5, at: start.addingTimeInterval(30))

        XCTAssertEqual(engine.round?.track.count, 2, "a fix 2 s after the last should be dropped")
    }
}
