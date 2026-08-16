import Foundation

enum DistanceUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case meters
    case yards

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .meters: return "m"
        case .yards: return "yd"
        }
    }

    var displayName: String {
        switch self {
        case .meters: return "Metres"
        case .yards: return "Yards"
        }
    }

    /// Everything is stored in metres; this is the conversion factor out.
    var metersPerUnit: Double {
        switch self {
        case .meters: return 1.0
        case .yards: return 0.9144
        }
    }
}

enum DistanceFormatter {
    static func convert(_ meters: Double, to unit: DistanceUnit) -> Double {
        meters / unit.metersPerUnit
    }

    /// "142" — whole units, for the big watch readouts.
    static func whole(_ meters: Double, in unit: DistanceUnit) -> String {
        let value = convert(meters, to: unit)
        guard value.isFinite else { return "--" }
        return String(Int(value.rounded()))
    }

    /// "142 m"
    static func labelled(_ meters: Double, in unit: DistanceUnit) -> String {
        "\(whole(meters, in: unit)) \(unit.shortLabel)"
    }

    /// "142.4 m" — for statistics, where the extra digit is meaningful.
    static func precise(_ meters: Double, in unit: DistanceUnit) -> String {
        let value = convert(meters, to: unit)
        guard value.isFinite else { return "--" }
        return String(format: "%.1f %@", value, unit.shortLabel)
    }
}
