import Foundation

/// Imports course geometry from OpenStreetMap via the public Overpass API.
///
/// Free, no API key, no account. The trade-off is coverage: OSM golf data is mapped by
/// volunteers, so a big club is usually complete and a small one may have nothing at all.
/// Whatever comes back is editable afterwards, and greens can always be marked by hand
/// in `CourseEditorView` — this importer is a shortcut, never a dependency.
///
/// Relevant tagging: `leisure=golf_course` for the grounds, `golf=hole` for the
/// tee-to-green centre line (carrying `ref`, `par` and `handicap`), and `golf=green`
/// for the putting surface outline.
struct OverpassImporter {

    enum ImportError: LocalizedError {
        case requestFailed(Int)
        case emptyResult
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .requestFailed(let code):
                return "OpenStreetMap returned an error (\(code)). It rate-limits heavy use — wait a moment and try again."
            case .emptyResult:
                return "No golf courses matched that name in OpenStreetMap."
            case .transport(let message):
                return message
            }
        }
    }

    struct SearchResult: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        var locality: String?
        var center: GeoPoint
        var boundingBox: BoundingBox
    }

    struct BoundingBox: Hashable, Sendable {
        var minLatitude: Double
        var minLongitude: Double
        var maxLatitude: Double
        var maxLongitude: Double

        /// Overpass bbox filters are ordered south, west, north, east.
        var overpassLiteral: String {
            "\(minLatitude),\(minLongitude),\(maxLatitude),\(maxLongitude)"
        }

        /// Greens sometimes sit a few metres outside the mapped course boundary.
        func padded(byDegrees delta: Double = 0.002) -> BoundingBox {
            BoundingBox(
                minLatitude: minLatitude - delta,
                minLongitude: minLongitude - delta,
                maxLatitude: maxLatitude + delta,
                maxLongitude: maxLongitude + delta
            )
        }
    }

    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Finds candidate courses by name. Case-insensitive substring match.
    func searchCourses(named query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }

        let request = """
        [out:json][timeout:30];
        nwr["leisure"="golf_course"]["name"~"\(escape(trimmed))",i];
        out center bb tags;
        """

        let response = try await run(request)
        let results = response.elements.compactMap(searchResult(from:))
        guard !results.isEmpty else { throw ImportError.emptyResult }
        return results
    }

    /// Finds courses near a point, for the "courses around me" case.
    func searchCourses(near point: GeoPoint, radiusMetres: Int = 25_000) async throws -> [SearchResult] {
        let request = """
        [out:json][timeout:30];
        nwr["leisure"="golf_course"](around:\(radiusMetres),\(point.latitude),\(point.longitude));
        out center bb tags;
        """

        let response = try await run(request)
        let results = response.elements.compactMap(searchResult(from:))
        guard !results.isEmpty else { throw ImportError.emptyResult }
        return results
            .sorted { Geodesy.distance(from: point, to: $0.center) < Geodesy.distance(from: point, to: $1.center) }
    }

    /// Pulls the hole lines, greens and tees inside a course's bounding box and
    /// assembles them into a `Course`.
    func importCourse(_ result: SearchResult) async throws -> Course {
        let bbox = result.boundingBox.padded().overpassLiteral
        let request = """
        [out:json][timeout:60];
        (
          way["golf"="hole"](\(bbox));
          way["golf"="green"](\(bbox));
          way["golf"="tee"](\(bbox));
        );
        out geom tags;
        """

        let response = try await run(request)
        let holes = assembleHoles(from: response.elements)
        guard !holes.isEmpty else { throw ImportError.emptyResult }

        return Course(
            name: result.name,
            locality: result.locality,
            holes: holes,
            source: .openStreetMap
        )
    }

    // MARK: - Assembly

    /// Greens carry no hole number in OSM, so they are matched to the `golf=hole`
    /// centre line whose far end they sit closest to. Where a course has greens mapped
    /// but no hole lines, holes are synthesised in file order for the user to renumber.
    private func assembleHoles(from elements: [Element]) -> [Hole] {
        let holeWays = elements.filter { $0.tags?["golf"] == "hole" }
        let greenWays = elements.filter { $0.tags?["golf"] == "green" }
        let teeWays = elements.filter { $0.tags?["golf"] == "tee" }

        let greens: [(polygon: [GeoPoint], center: GeoPoint)] = greenWays.compactMap { way in
            let polygon = way.points
            guard polygon.count >= 3, let center = Geodesy.centroid(of: polygon) else { return nil }
            return (polygon, center)
        }

        guard !holeWays.isEmpty else {
            return greens.enumerated().map { index, green in
                Hole(number: index + 1, green: Green(polygon: green.polygon))
            }
        }

        var usedGreenIndices = Set<Int>()
        var holes: [Hole] = []

        // Sort by hole number so the greedy green matching walks the course in order.
        let ordered = holeWays.sorted { (holeNumber(of: $0) ?? .max) < (holeNumber(of: $1) ?? .max) }

        for (index, way) in ordered.enumerated() {
            let line = way.points
            guard !line.isEmpty else { continue }
            let number = holeNumber(of: way) ?? (index + 1)
            let par = way.tags?["par"].flatMap(Int.init) ?? 4
            let strokeIndex = way.tags?["handicap"].flatMap(Int.init)

            // The hole way is drawn tee → green, so its last node is at the green.
            let greenEnd = line[line.count - 1]
            var matchedGreen: Green?
            if let match = nearestUnusedGreen(to: greenEnd, greens: greens, used: usedGreenIndices) {
                usedGreenIndices.insert(match.index)
                matchedGreen = Green(polygon: greens[match.index].polygon)
            }

            let tees = nearestTee(to: line[0], among: teeWays).map {
                [TeeBox(name: "Tee", point: $0)]
            } ?? [TeeBox(name: "Tee", point: line[0])]

            holes.append(
                Hole(
                    number: number,
                    par: par,
                    strokeIndex: strokeIndex,
                    green: matchedGreen,
                    tees: tees
                )
            )
        }

        return holes.sorted { $0.number < $1.number }
    }

    /// Nearest unclaimed green within 150 m. Beyond that the hole line probably just
    /// stops short of an unmapped green, and a wrong match is worse than none.
    private func nearestUnusedGreen(
        to point: GeoPoint,
        greens: [(polygon: [GeoPoint], center: GeoPoint)],
        used: Set<Int>
    ) -> (index: Int, distance: Double)? {
        var best: (index: Int, distance: Double)?
        for (index, green) in greens.enumerated() where !used.contains(index) {
            let distance = Geodesy.distance(from: point, to: green.center)
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (index, distance)
            }
        }
        guard let best, best.distance <= 150 else { return nil }
        return best
    }

    private func nearestTee(to point: GeoPoint, among teeWays: [Element]) -> GeoPoint? {
        var best: (point: GeoPoint, distance: Double)?
        for way in teeWays {
            guard let centre = Geodesy.centroid(of: way.points) else { continue }
            let distance = Geodesy.distance(from: point, to: centre)
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (centre, distance)
            }
        }
        guard let best, best.distance <= 100 else { return nil }
        return best.point
    }

    private func holeNumber(of element: Element) -> Int? {
        guard let ref = element.tags?["ref"] ?? element.tags?["name"] else { return nil }
        // "7", "Hole 7" and "7th" all appear in the wild.
        let digits = ref.compactMap { $0.isNumber ? $0 : nil }
        return Int(String(digits))
    }

    // MARK: - Transport

    private func run(_ query: String) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Overpass asks consumers to identify themselves so it can rate-limit fairly.
        request.setValue("Fairway-Golf/1.0", forHTTPHeaderField: "User-Agent")
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")"
            .data(using: .utf8)
        request.timeoutInterval = 60

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ImportError.requestFailed(http.statusCode)
            }
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as ImportError {
            throw error
        } catch {
            throw ImportError.transport(error.localizedDescription)
        }
    }

    /// Overpass regex metacharacters would otherwise break the query for a course
    /// with a `(` or `.` in its name.
    private func escape(_ value: String) -> String {
        var escaped = ""
        for character in value {
            if "\\.^$|()[]{}*+?\"".contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    private func searchResult(from element: Element) -> SearchResult? {
        guard let tags = element.tags, let name = tags["name"] else { return nil }
        guard let centre = element.centerPoint else { return nil }

        let locality = tags["addr:city"]
            ?? tags["addr:suburb"]
            ?? tags["addr:state"]
            ?? tags["is_in"]

        let bounds = element.bounds.map {
            BoundingBox(
                minLatitude: $0.minlat,
                minLongitude: $0.minlon,
                maxLatitude: $0.maxlat,
                maxLongitude: $0.maxlon
            )
        } ?? BoundingBox(
            // A node-tagged course has no extent; a ~2 km box around it covers 18 holes.
            minLatitude: centre.latitude - 0.012,
            minLongitude: centre.longitude - 0.012,
            maxLatitude: centre.latitude + 0.012,
            maxLongitude: centre.longitude + 0.012
        )

        return SearchResult(
            id: "\(element.type)/\(element.id)",
            name: name,
            locality: locality,
            center: centre,
            boundingBox: bounds
        )
    }

    // MARK: - Wire format

    private struct Response: Decodable {
        var elements: [Element]
    }

    fileprivate struct Element: Decodable {
        var type: String
        var id: Int
        var lat: Double?
        var lon: Double?
        var center: LatLon?
        var bounds: Bounds?
        var geometry: [LatLon]?
        var tags: [String: String]?

        var points: [GeoPoint] {
            geometry?.map { GeoPoint(latitude: $0.lat, longitude: $0.lon) } ?? []
        }

        var centerPoint: GeoPoint? {
            if let center { return GeoPoint(latitude: center.lat, longitude: center.lon) }
            if let lat, let lon { return GeoPoint(latitude: lat, longitude: lon) }
            return Geodesy.centroid(of: points)
        }
    }

    fileprivate struct LatLon: Decodable {
        var lat: Double
        var lon: Double
    }

    fileprivate struct Bounds: Decodable {
        var minlat: Double
        var minlon: Double
        var maxlat: Double
        var maxlon: Double
    }
}
