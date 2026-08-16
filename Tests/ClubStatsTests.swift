import XCTest

final class ClubStatsTests: XCTestCase {

    private let origin = GeoPoint(latitude: -36.8509, longitude: 174.7645)

    private var bag: Bag { .standard }

    private func club(_ abbreviation: String) -> Club {
        bag.clubs.first { $0.abbreviation == abbreviation }!
    }

    /// Builds a closed shot of an exact ground distance, so assertions can be tight.
    private func shot(
        club: Club?,
        distance: Double,
        accuracy: Double = 5,
        isPenalty: Bool = false,
        hole: Int = 1
    ) -> Shot {
        Shot(
            holeNumber: hole,
            clubID: club?.id,
            origin: origin,
            end: Geodesy.destination(from: origin, bearing: 0, distance: distance),
            originAccuracy: accuracy,
            endAccuracy: accuracy,
            isPenalty: isPenalty
        )
    }

    private func round(_ shots: [Shot], startedAt: Date = Date()) -> Round {
        Round(
            courseID: UUID(),
            courseName: "Test Links",
            startedAt: startedAt,
            finishedAt: startedAt.addingTimeInterval(4 * 3600),
            holes: [HoleScore(holeNumber: 1, par: 4, shots: shots)]
        )
    }

    private func statistics(_ shots: [Shot], settings: AppSettings = .default) -> [ClubStatistics] {
        ClubStatsEngine.statistics(rounds: [round(shots)], bag: bag, settings: settings)
    }

    // MARK: - Averaging

    func testAverageIsTheMeanOfLoggedDistances() throws {
        let seven = club("7i")
        let stats = statistics([
            shot(club: seven, distance: 140),
            shot(club: seven, distance: 150),
            shot(club: seven, distance: 145)
        ])

        let sevenStats = try XCTUnwrap(stats.first { $0.club.id == seven.id })
        XCTAssertEqual(sevenStats.sampleCount, 3)
        XCTAssertEqual(sevenStats.average, 145, accuracy: 0.5)
        XCTAssertEqual(sevenStats.median, 145, accuracy: 0.5)
        XCTAssertEqual(sevenStats.shortest, 140, accuracy: 0.5)
        XCTAssertEqual(sevenStats.longest, 150, accuracy: 0.5)
    }

    /// The whole point of trimming: one shank shouldn't move the number you play to.
    func testTrimmingRemovesTheExtremesOnceThereAreEnoughSamples() throws {
        let seven = club("7i")
        var shots = (0..<10).map { _ in shot(club: seven, distance: 145) }
        shots.append(shot(club: seven, distance: 40))    // duffed
        shots.append(shot(club: seven, distance: 260))   // caught a cart path

        let trimmed = try XCTUnwrap(
            statistics(shots).first { $0.club.id == seven.id }
        )
        var untrimmedSettings = AppSettings.default
        untrimmedSettings.trimOutliers = false
        let untrimmed = try XCTUnwrap(
            statistics(shots, settings: untrimmedSettings).first { $0.club.id == seven.id }
        )

        XCTAssertEqual(trimmed.average, 145, accuracy: 1.0)
        XCTAssertGreaterThan(untrimmed.average, trimmed.average)
        // Sample count always reports what was actually logged, not what survived trimming.
        XCTAssertEqual(trimmed.sampleCount, 12)
    }

    func testTrimmingIsSkippedForSmallSamples() throws {
        let seven = club("7i")
        let stats = try XCTUnwrap(
            statistics([
                shot(club: seven, distance: 100),
                shot(club: seven, distance: 150),
                shot(club: seven, distance: 200)
            ]).first { $0.club.id == seven.id }
        )
        XCTAssertEqual(stats.average, 150, accuracy: 1.0)
        XCTAssertEqual(stats.sampleCount, 3)
    }

    // MARK: - Filtering

    func testPuttsAreExcludedEntirely() {
        let stats = statistics([
            shot(club: club("Pt"), distance: 8),
            shot(club: club("Pt"), distance: 2)
        ])
        XCTAssertTrue(stats.isEmpty)
    }

    func testPenaltyStrokesAreExcluded() {
        let stats = statistics([
            shot(club: club("Dr"), distance: 200, isPenalty: true)
        ])
        XCTAssertTrue(stats.isEmpty)
    }

    func testShotsWithPoorGPSAreExcluded() {
        let stats = statistics([
            shot(club: club("Dr"), distance: 220, accuracy: 40)
        ])
        XCTAssertTrue(stats.isEmpty)
    }

    func testOpenShotsAreExcludedBecauseTheirDistanceIsUnknown() {
        let driver = club("Dr")
        let open = Shot(holeNumber: 1, clubID: driver.id, origin: origin, originAccuracy: 5)
        XCTAssertTrue(ClubStatsEngine.statistics(
            rounds: [round([open])],
            bag: bag
        ).isEmpty)
    }

    /// A topped 6 iron shouldn't count; a deliberate 40 m wedge should.
    func testShortShotsCountForWedgesOnly() throws {
        let stats = statistics([
            shot(club: club("6i"), distance: 20),
            shot(club: club("SW"), distance: 20)
        ])

        XCTAssertNil(stats.first { $0.club.abbreviation == "6i" })
        let wedge = try XCTUnwrap(stats.first { $0.club.abbreviation == "SW" })
        XCTAssertEqual(wedge.average, 20, accuracy: 0.5)
    }

    func testImplausiblyLongShotsAreRejected() {
        // Driving the cart to the next tee with a shot still open.
        let stats = statistics([shot(club: club("Dr"), distance: 900)])
        XCTAssertTrue(stats.isEmpty)
    }

    // MARK: - Ordering, gapping and selection

    func testStatisticsAreOrderedLongestFirst() {
        let stats = statistics([
            shot(club: club("9i"), distance: 110),
            shot(club: club("Dr"), distance: 230),
            shot(club: club("7i"), distance: 145)
        ])
        XCTAssertEqual(stats.map(\.club.abbreviation), ["Dr", "7i", "9i"])
    }

    func testGapsAreMeasuredBetweenConsecutiveClubs() {
        let stats = statistics([
            shot(club: club("Dr"), distance: 230),
            shot(club: club("7i"), distance: 145),
            shot(club: club("9i"), distance: 115)
        ])
        let gaps = ClubStatsEngine.gaps(from: stats)

        XCTAssertEqual(gaps.count, 2)
        XCTAssertEqual(gaps[0].gap, 85, accuracy: 1.0)
        XCTAssertEqual(gaps[1].gap, 30, accuracy: 1.0)
    }

    /// You pull the shortest club that still gets there, not the closest average.
    func testRecommendationPicksTheShortestClubThatReaches() throws {
        let stats = statistics([
            shot(club: club("7i"), distance: 145),
            shot(club: club("8i"), distance: 132),
            shot(club: club("9i"), distance: 118)
        ])

        XCTAssertEqual(
            ClubStatsEngine.recommendedClub(for: 130, statistics: stats)?.club.abbreviation,
            "8i"
        )
        XCTAssertEqual(
            ClubStatsEngine.recommendedClub(for: 144, statistics: stats)?.club.abbreviation,
            "7i"
        )
    }

    func testRecommendationFallsBackToTheLongestClubWhenNothingReaches() {
        let stats = statistics([shot(club: club("7i"), distance: 145)])
        XCTAssertEqual(
            ClubStatsEngine.recommendedClub(for: 300, statistics: stats)?.club.abbreviation,
            "7i"
        )
    }

    func testReliabilityThresholdFlagsThinSamples() throws {
        let seven = club("7i")
        let thin = try XCTUnwrap(
            statistics([shot(club: seven, distance: 145)]).first
        )
        let solid = try XCTUnwrap(
            statistics((0..<6).map { _ in shot(club: seven, distance: 145) }).first
        )

        XCTAssertFalse(thin.isReliable)
        XCTAssertTrue(solid.isReliable)
    }

    // MARK: - Summary maths

    func testStandardDeviationIsZeroForIdenticalShots() throws {
        let stats = try XCTUnwrap(
            statistics((0..<5).map { _ in shot(club: club("7i"), distance: 145) }).first
        )
        XCTAssertEqual(stats.standardDeviation, 0, accuracy: 0.1)
        XCTAssertEqual(stats.typicalRange.lowerBound, stats.average, accuracy: 0.2)
    }
}
