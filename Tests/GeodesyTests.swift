import XCTest

final class GeodesyTests: XCTestCase {

    /// Somewhere on an Auckland fairway. The exact spot is irrelevant; what matters is
    /// that the maths is exercised at a real latitude rather than at 0,0.
    private let origin = GeoPoint(latitude: -36.8509, longitude: 174.7645)

    // MARK: - Distance and bearing

    func testDistanceIsSymmetricAndZeroForIdenticalPoints() {
        let other = Geodesy.destination(from: origin, bearing: 42, distance: 250)
        XCTAssertEqual(Geodesy.distance(from: origin, to: origin), 0, accuracy: 0.001)
        XCTAssertEqual(
            Geodesy.distance(from: origin, to: other),
            Geodesy.distance(from: other, to: origin),
            accuracy: 0.001
        )
    }

    func testDestinationAndDistanceAreInverses() {
        for distance in [10.0, 137.0, 400.0, 5_000.0] {
            for bearing in [0.0, 73.0, 180.0, 289.0] {
                let target = Geodesy.destination(from: origin, bearing: bearing, distance: distance)
                XCTAssertEqual(
                    Geodesy.distance(from: origin, to: target),
                    distance,
                    accuracy: 0.05,
                    "round trip failed at \(distance) m on bearing \(bearing)"
                )
            }
        }
    }

    func testBearingMatchesTheDirectionTravelled() {
        let north = Geodesy.destination(from: origin, bearing: 0, distance: 200)
        let east = Geodesy.destination(from: origin, bearing: 90, distance: 200)

        XCTAssertEqual(Geodesy.bearing(from: origin, to: north), 0, accuracy: 0.1)
        XCTAssertEqual(Geodesy.bearing(from: origin, to: east), 90, accuracy: 0.1)
    }

    func testAngleDifferenceWrapsAroundNorth() {
        XCTAssertEqual(Geodesy.angleDifference(10, 350), 20, accuracy: 0.0001)
        XCTAssertEqual(Geodesy.angleDifference(350, 10), -20, accuracy: 0.0001)
        XCTAssertEqual(Geodesy.angleDifference(90, 90), 0, accuracy: 0.0001)
    }

    // MARK: - Greens

    /// A 30 m square green, 150 m due north of the player. Front and back should come
    /// out 15 m either side of the centre, because the player is square to the green.
    func testGreenDistancesSplitFrontAndBackAlongTheLineOfPlay() throws {
        let centre = GeoPoint(latitude: -36.8500, longitude: 174.7645)
        let player = Geodesy.destination(from: centre, bearing: 180, distance: 150)
        let halfDiagonal = 15 * 2.0.squareRoot()
        let green = [45.0, 135.0, 225.0, 315.0].map {
            Geodesy.destination(from: centre, bearing: $0, distance: halfDiagonal)
        }

        let distances = try XCTUnwrap(Geodesy.greenDistances(from: player, green: green))

        XCTAssertEqual(distances.center, 150, accuracy: 0.5)
        XCTAssertEqual(distances.front, 135, accuracy: 0.5)
        XCTAssertEqual(distances.back, 165, accuracy: 0.5)
        XCTAssertEqual(distances.depth, 30, accuracy: 1.0)
    }

    /// Approaching the same green from the side, the player sees its width, not its
    /// depth — the projection has to follow the line of play, not the compass.
    func testGreenDepthFollowsTheApproachAngle() {
        let centre = GeoPoint(latitude: -36.8500, longitude: 174.7645)
        // A green twice as long north–south as it is wide east–west.
        let green = [
            Geodesy.destination(from: centre, bearing: 0, distance: 30),
            Geodesy.destination(from: centre, bearing: 90, distance: 15),
            Geodesy.destination(from: centre, bearing: 180, distance: 30),
            Geodesy.destination(from: centre, bearing: 270, distance: 15)
        ]

        let fromSouth = try? XCTUnwrap(
            Geodesy.greenDistances(
                from: Geodesy.destination(from: centre, bearing: 180, distance: 150),
                green: green
            )
        )
        let fromWest = try? XCTUnwrap(
            Geodesy.greenDistances(
                from: Geodesy.destination(from: centre, bearing: 270, distance: 150),
                green: green
            )
        )

        XCTAssertEqual(fromSouth?.depth ?? 0, 60, accuracy: 2)
        XCTAssertEqual(fromWest?.depth ?? 0, 30, accuracy: 2)
    }

    /// A pin dropped by hand has no outline, so all three numbers are the same one.
    func testSinglePointGreenReportsOneDistance() {
        let pin = Geodesy.destination(from: origin, bearing: 0, distance: 120)
        let distances = try? XCTUnwrap(Geodesy.greenDistances(from: origin, green: [pin]))

        XCTAssertEqual(distances?.front ?? 0, 120, accuracy: 0.5)
        XCTAssertEqual(distances?.center ?? 0, 120, accuracy: 0.5)
        XCTAssertEqual(distances?.back ?? 0, 120, accuracy: 0.5)
        XCTAssertEqual(distances?.depth ?? -1, 0, accuracy: 0.5)
    }

    func testGreenDistancesAreNilForAnEmptyOutline() {
        XCTAssertNil(Geodesy.greenDistances(from: origin, green: []))
    }

    func testDistancesNeverGoNegativeStandingOnTheGreen() {
        let centre = GeoPoint(latitude: -36.8500, longitude: 174.7645)
        let green = [0.0, 90.0, 180.0, 270.0].map {
            Geodesy.destination(from: centre, bearing: $0, distance: 15)
        }
        // Standing just inside the front edge, the front of the green is behind you.
        let player = Geodesy.destination(from: centre, bearing: 180, distance: 10)
        let distances = try? XCTUnwrap(Geodesy.greenDistances(from: player, green: green))

        XCTAssertGreaterThanOrEqual(distances?.front ?? -1, 0)
        XCTAssertGreaterThanOrEqual(distances?.back ?? -1, 0)
    }

    // MARK: - Centroid and containment

    func testCentroidOfASymmetricRingIsItsMiddle() {
        let centre = GeoPoint(latitude: -36.8500, longitude: 174.7645)
        let ring = stride(from: 0.0, to: 360.0, by: 30.0).map {
            Geodesy.destination(from: centre, bearing: $0, distance: 20)
        }

        let computed = try? XCTUnwrap(Geodesy.centroid(of: ring))
        XCTAssertEqual(Geodesy.distance(from: centre, to: computed ?? centre), 0, accuracy: 1.0)
    }

    /// OSM closes its ways by repeating the first node; that duplicate must not drag
    /// the centroid toward one corner.
    func testCentroidIgnoresARepeatedClosingVertex() {
        let centre = GeoPoint(latitude: -36.8500, longitude: 174.7645)
        var ring = [0.0, 90.0, 180.0, 270.0].map {
            Geodesy.destination(from: centre, bearing: $0, distance: 20)
        }
        let open = try? XCTUnwrap(Geodesy.centroid(of: ring))
        ring.append(ring[0])
        let closed = try? XCTUnwrap(Geodesy.centroid(of: ring))

        XCTAssertEqual(
            Geodesy.distance(from: open ?? centre, to: closed ?? centre),
            0,
            accuracy: 0.5
        )
    }

    func testContainsDistinguishesInsideFromOutside() {
        let centre = GeoPoint(latitude: -36.8500, longitude: 174.7645)
        let green = [0.0, 90.0, 180.0, 270.0].map {
            Geodesy.destination(from: centre, bearing: $0, distance: 20)
        }

        XCTAssertTrue(Geodesy.contains(centre, polygon: green))
        XCTAssertFalse(
            Geodesy.contains(
                Geodesy.destination(from: centre, bearing: 45, distance: 100),
                polygon: green
            )
        )
    }
}
