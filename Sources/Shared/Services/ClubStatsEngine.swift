import Foundation

/// Everything the app knows about how far one club actually goes for this player.
///
/// A word on what these numbers are. GPS measures where the ball came to **rest**,
/// so every figure here is *total* distance — carry plus roll. Expect them to read
/// noticeably longer than launch-monitor carry numbers, and to move with firm ground,
/// wind and slope. That makes them excellent for gapping and club selection on the
/// course you actually play, and wrong for comparing against a fitting session.
struct ClubStatistics: Identifiable, Hashable, Sendable {
    var club: Club
    var sampleCount: Int
    /// Trimmed mean when there are enough samples, plain mean otherwise. Metres.
    var average: Double
    var median: Double
    var shortest: Double
    var longest: Double
    var standardDeviation: Double
    /// Most recent samples first, for the sparkline on the club detail screen.
    var recent: [Double]

    var id: UUID { club.id }

    /// Roughly two thirds of shots land in here. What you should actually plan around.
    var typicalRange: ClosedRange<Double> {
        let low = max(0, average - standardDeviation)
        let high = average + standardDeviation
        return low...max(low, high)
    }

    /// Fewer than this and the average is a rumour, not a number.
    var isReliable: Bool { sampleCount >= 5 }
}

/// The distance you give up stepping down one club. Big gaps are where scores leak.
struct ClubGap: Identifiable, Hashable, Sendable {
    var longer: Club
    var shorter: Club
    var gap: Double

    var id: String { "\(longer.id)-\(shorter.id)" }
}

enum ClubStatsEngine {

    /// Shots beyond this are a GPS glitch or a drive between holes, not a golf shot.
    private static let implausibleDistanceCeiling: Double = 400

    /// Per-club statistics across the supplied rounds, longest club first.
    /// Clubs with no usable samples are omitted entirely rather than shown as zero.
    static func statistics(
        rounds: [Round],
        bag: Bag,
        settings: AppSettings = .default
    ) -> [ClubStatistics] {
        let clubsByID = Dictionary(uniqueKeysWithValues: bag.clubs.map { ($0.id, $0) })

        // Newest first, so `recent` is genuinely recent.
        let shots = rounds
            .sorted { $0.startedAt > $1.startedAt }
            .flatMap(\.allShots)

        var samplesByClub: [UUID: [Double]] = [:]
        for shot in shots {
            guard
                let clubID = shot.clubID,
                let club = clubsByID[clubID],
                let distance = usableDistance(for: shot, club: club, settings: settings)
            else { continue }
            samplesByClub[clubID, default: []].append(distance)
        }

        return samplesByClub.compactMap { clubID, samples -> ClubStatistics? in
            guard let club = clubsByID[clubID], !samples.isEmpty else { return nil }
            let considered = settings.trimOutliers ? trimmed(samples) : samples
            guard !considered.isEmpty else { return nil }

            return ClubStatistics(
                club: club,
                sampleCount: samples.count,
                average: considered.mean,
                median: considered.median,
                shortest: samples.min() ?? 0,
                longest: samples.max() ?? 0,
                standardDeviation: considered.standardDeviation,
                recent: Array(samples.prefix(10))
            )
        }
        .sorted { $0.average > $1.average }
    }

    /// Gaps between consecutive clubs by measured average — not by loft, because the
    /// point is to find the clubs that overlap in practice.
    static func gaps(from statistics: [ClubStatistics]) -> [ClubGap] {
        let ordered = statistics.sorted { $0.average > $1.average }
        guard ordered.count > 1 else { return [] }
        return (0..<(ordered.count - 1)).map { index in
            ClubGap(
                longer: ordered[index].club,
                shorter: ordered[index + 1].club,
                gap: ordered[index].average - ordered[index + 1].average
            )
        }
    }

    /// The shortest club whose average still covers `distance` — i.e. the club you'd
    /// pull. Falls back to the longest club in the bag when nothing reaches.
    static func recommendedClub(
        for distance: Double,
        statistics: [ClubStatistics]
    ) -> ClubStatistics? {
        let reaching = statistics
            .filter { $0.average >= distance }
            .sorted { $0.average < $1.average }
        return reaching.first ?? statistics.max { $0.average < $1.average }
    }

    // MARK: - Filtering

    /// Returns the shot's distance if it belongs in the statistics, `nil` if it doesn't.
    private static func usableDistance(
        for shot: Shot,
        club: Club,
        settings: AppSettings
    ) -> Double? {
        guard !shot.isPenalty else { return nil }
        guard club.kind.contributesToDistanceStats else { return nil }
        guard let distance = shot.measuredDistance else { return nil }
        guard shot.worstAccuracy <= settings.statsAccuracyCeiling else { return nil }
        guard distance < implausibleDistanceCeiling else { return nil }

        // Wedges are supposed to hit partial shots — filtering short ones would
        // throw away most of the wedge data. Every other club, a short reading
        // means a duff or a chip and would drag the average down misleadingly.
        if club.kind != .wedge, distance < settings.minimumFullSwingDistance {
            return nil
        }
        return distance
    }

    /// Symmetric 10% trim, applied only once there are enough samples that removing
    /// two of them still leaves something meaningful.
    private static func trimmed(_ samples: [Double]) -> [Double] {
        guard samples.count >= 8 else { return samples }
        let sorted = samples.sorted()
        let cut = Int((Double(sorted.count) * 0.1).rounded(.down))
        guard cut > 0, sorted.count - (cut * 2) >= 3 else { return sorted }
        return Array(sorted[cut..<(sorted.count - cut)])
    }
}

extension Array where Element == Double {
    var mean: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }

    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    /// Sample standard deviation. Zero for a single sample, which is the honest answer.
    var standardDeviation: Double {
        guard count > 1 else { return 0 }
        let m = mean
        let variance = reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(count - 1)
        return variance.squareRoot()
    }
}
