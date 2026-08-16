import Foundation

struct AppSettings: Codable, Hashable, Sendable {
    var distanceUnit: DistanceUnit
    /// Shots bounded by a fix worse than this (metres) are excluded from club stats.
    /// 15 m is loose enough to keep a round under tree cover and tight enough to
    /// reject the garbage fixes you get in the first seconds after a cold start.
    var statsAccuracyCeiling: Double
    /// Shots shorter than this are treated as chips/taps and left out of full-swing
    /// averages. Applies to every club except wedges, where short shots are the point.
    var minimumFullSwingDistance: Double
    /// Drop the top and bottom 10% of a club's samples before averaging, once there
    /// are enough shots for it to mean anything. Kills shanks and topped drives.
    var trimOutliers: Bool
    /// Keep the watch screen showing distance rather than dimming between shots.
    var keepWatchScreenActive: Bool

    static let `default` = AppSettings(
        distanceUnit: .meters,
        statsAccuracyCeiling: 15,
        minimumFullSwingDistance: 30,
        trimOutliers: true,
        keepWatchScreenActive: true
    )
}
