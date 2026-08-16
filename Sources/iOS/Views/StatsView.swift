import Charts
import SwiftUI

/// Per-club distances, built entirely from shots you logged on the course.
struct StatsView: View {
    @Environment(AppModel.self) private var model

    private var statistics: [ClubStatistics] { model.store.clubStatistics }

    var body: some View {
        NavigationStack {
            List {
                if statistics.isEmpty {
                    ContentUnavailableView {
                        Label("No club data yet", systemImage: "chart.bar")
                    } description: {
                        Text("Log shots with a club during a round and your distances build up here. Five or so shots per club before the numbers mean much.")
                    }
                } else {
                    Section {
                        GappingChart(statistics: statistics, unit: model.unit)
                            .frame(height: max(220, CGFloat(statistics.count) * 26))
                    } header: {
                        Text("Distance by club")
                    } footer: {
                        Text("Bars show your average; the line through each is one standard deviation either side — roughly two thirds of your shots.")
                    }

                    Section("Clubs") {
                        ForEach(statistics) { stat in
                            NavigationLink {
                                ClubDetailView(statistics: stat)
                            } label: {
                                ClubStatRow(statistics: stat, unit: model.unit)
                            }
                        }
                    }

                    if !model.store.clubGaps.isEmpty {
                        Section {
                            ForEach(model.store.clubGaps) { gap in
                                HStack {
                                    Text("\(gap.longer.abbreviation) → \(gap.shorter.abbreviation)")
                                        .font(.subheadline.monospaced())
                                    Spacer()
                                    Text(DistanceFormatter.labelled(gap.gap, in: model.unit))
                                        .monospacedDigit()
                                        .foregroundStyle(gap.gap > 25 ? .orange : .secondary)
                                }
                            }
                        } header: {
                            Text("Gapping")
                        } footer: {
                            Text("Gaps wider than about 25 m are where you have no club for the shot. Highlighted in orange.")
                        }
                    }
                }
            }
            .navigationTitle("Clubs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BagEditorView()
                    } label: {
                        Label("My bag", systemImage: "bag")
                    }
                }
            }
        }
    }
}

struct GappingChart: View {
    var statistics: [ClubStatistics]
    var unit: DistanceUnit

    var body: some View {
        Chart(statistics) { stat in
            BarMark(
                x: .value("Distance", DistanceFormatter.convert(stat.average, to: unit)),
                y: .value("Club", stat.club.abbreviation)
            )
            .foregroundStyle(stat.isReliable ? Color.accentColor : Color.secondary.opacity(0.5))

            RuleMark(
                xStart: .value("Low", DistanceFormatter.convert(stat.typicalRange.lowerBound, to: unit)),
                xEnd: .value("High", DistanceFormatter.convert(stat.typicalRange.upperBound, to: unit)),
                y: .value("Club", stat.club.abbreviation)
            )
            .foregroundStyle(.primary.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxisLabel(unit.displayName)
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading)
        }
    }
}

struct ClubStatRow: View {
    var statistics: ClubStatistics
    var unit: DistanceUnit

    var body: some View {
        HStack {
            Text(statistics.club.abbreviation)
                .font(.headline.monospaced())
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(statistics.club.name)
                Text("\(statistics.sampleCount) shot\(statistics.sampleCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(statistics.isReliable ? .secondary : .orange)
            }

            Spacer()

            Text(DistanceFormatter.whole(statistics.average, in: unit))
                .font(.title3.monospacedDigit())
        }
    }
}
