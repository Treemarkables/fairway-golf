import Foundation

enum ClubKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case driver
    case wood
    case hybrid
    case iron
    case wedge
    case putter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .driver: return "Driver"
        case .wood: return "Fairway Wood"
        case .hybrid: return "Hybrid"
        case .iron: return "Iron"
        case .wedge: return "Wedge"
        case .putter: return "Putter"
        }
    }

    /// Putters are excluded from distance statistics — GPS cannot meaningfully measure
    /// a two-metre tap-in, and including them destroys the gapping chart.
    var contributesToDistanceStats: Bool { self != .putter }
}

struct Club: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Short label for the watch face, e.g. "7i", "PW", "3W".
    var abbreviation: String
    /// Full name for the iPhone UI, e.g. "7 Iron".
    var name: String
    var kind: ClubKind
    var loft: Double?
    /// Descending expected distance. Drives the order of the watch club picker.
    var sortOrder: Int
    var isInBag: Bool

    init(
        id: UUID = UUID(),
        abbreviation: String,
        name: String,
        kind: ClubKind,
        loft: Double? = nil,
        sortOrder: Int,
        isInBag: Bool = true
    ) {
        self.id = id
        self.abbreviation = abbreviation
        self.name = name
        self.kind = kind
        self.loft = loft
        self.sortOrder = sortOrder
        self.isInBag = isInBag
    }
}

struct Bag: Codable, Hashable, Sendable {
    var clubs: [Club]

    var inBag: [Club] {
        clubs.filter(\.isInBag).sorted { $0.sortOrder < $1.sortOrder }
    }

    func club(withID id: UUID) -> Club? {
        clubs.first { $0.id == id }
    }

    /// A conventional 14-club set, edited in Settings → My Bag.
    /// Nothing downstream assumes these specific clubs exist.
    ///
    /// Deliberately a `let`: club identity has to be stable, because shots reference
    /// clubs by ID. Rebuilding the set on every access would mint fresh UUIDs and
    /// orphan every shot already logged against the previous copy.
    static let standard: Bag = {
        var order = 0
        func next() -> Int { defer { order += 1 }; return order }
        return Bag(clubs: [
            Club(abbreviation: "Dr", name: "Driver", kind: .driver, loft: 10.5, sortOrder: next()),
            Club(abbreviation: "3W", name: "3 Wood", kind: .wood, loft: 15, sortOrder: next()),
            Club(abbreviation: "5W", name: "5 Wood", kind: .wood, loft: 18, sortOrder: next()),
            Club(abbreviation: "4H", name: "4 Hybrid", kind: .hybrid, loft: 22, sortOrder: next()),
            Club(abbreviation: "5i", name: "5 Iron", kind: .iron, loft: 25, sortOrder: next()),
            Club(abbreviation: "6i", name: "6 Iron", kind: .iron, loft: 28, sortOrder: next()),
            Club(abbreviation: "7i", name: "7 Iron", kind: .iron, loft: 32, sortOrder: next()),
            Club(abbreviation: "8i", name: "8 Iron", kind: .iron, loft: 36, sortOrder: next()),
            Club(abbreviation: "9i", name: "9 Iron", kind: .iron, loft: 40, sortOrder: next()),
            Club(abbreviation: "PW", name: "Pitching Wedge", kind: .wedge, loft: 45, sortOrder: next()),
            Club(abbreviation: "GW", name: "Gap Wedge", kind: .wedge, loft: 50, sortOrder: next()),
            Club(abbreviation: "SW", name: "Sand Wedge", kind: .wedge, loft: 56, sortOrder: next()),
            Club(abbreviation: "LW", name: "Lob Wedge", kind: .wedge, loft: 60, sortOrder: next()),
            Club(abbreviation: "Pt", name: "Putter", kind: .putter, sortOrder: next())
        ])
    }()
}
