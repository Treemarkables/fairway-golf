import Charts
import SwiftUI

struct ClubDetailView: View {
    @Environment(AppModel.self) private var model
    var statistics: ClubStatistics

    private var unit: DistanceUnit { model.unit }

    /// `statistics.recent` is newest first; the chart reads left to right in time order.
    private struct RecentShot: Identifiable {
        let id: Int
        let distance: Double
    }

    private var recentShots: [RecentShot] {
        statistics.recent
            .reversed()
            .enumerated()
            .map { RecentShot(id: $0.offset, distance: $0.element) }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Average", value: DistanceFormatter.precise(statistics.average, in: unit))
                LabeledContent("Median", value: DistanceFormatter.precise(statistics.median, in: unit))
                LabeledContent(
                    "Typical range",
                    value: "\(DistanceFormatter.whole(statistics.typicalRange.lowerBound, in: unit))–\(DistanceFormatter.labelled(statistics.typicalRange.upperBound, in: unit))"
                )
                LabeledContent("Shortest", value: DistanceFormatter.precise(statistics.shortest, in: unit))
                LabeledContent("Longest", value: DistanceFormatter.precise(statistics.longest, in: unit))
                LabeledContent("Consistency", value: "±\(DistanceFormatter.precise(statistics.standardDeviation, in: unit))")
                LabeledContent("Shots logged", value: "\(statistics.sampleCount)")
            } header: {
                Text(statistics.club.name)
            } footer: {
                if !statistics.isReliable {
                    Text("Only \(statistics.sampleCount) shots so far — treat this as a rough guide until there are five or more.")
                }
            }

            if statistics.recent.count > 1 {
                Section {
                    Chart(recentShots) { shot in
                        LineMark(
                            x: .value("Shot", shot.id),
                            y: .value("Distance", DistanceFormatter.convert(shot.distance, to: unit))
                        )
                        PointMark(
                            x: .value("Shot", shot.id),
                            y: .value("Distance", DistanceFormatter.convert(shot.distance, to: unit))
                        )
                    }
                    .chartXAxis(.hidden)
                    .chartYAxisLabel(unit.displayName)
                    .frame(height: 160)
                } header: {
                    Text("Recent shots")
                } footer: {
                    Text("Oldest to newest, most recent \(statistics.recent.count) shots.")
                }
            }

            Section {
                Text("These are **total** distances — where the ball came to rest, roll included. They'll read longer than launch-monitor carry numbers, and they move with firm ground, wind and slope. That makes them right for picking a club on your course, and wrong for comparing against a fitting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(statistics.club.abbreviation)
        .navigationBarTitleDisplayMode(.inline)
    }
}
