import SwiftUI

/// The screen you actually look at, standing over the ball. One number dominates —
/// distance to the middle of the green — with front and back either side of it, and
/// everything else kept small enough not to compete.
struct WatchDistanceView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        VStack(spacing: 2) {
            header

            if let distances = model.currentDistances {
                Text(DistanceFormatter.whole(distances.center, in: model.unit))
                    .font(.system(size: 62, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                HStack {
                    edge("F", distances.front)
                    Spacer()
                    Text(model.unit.shortLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    edge("B", distances.back)
                }
            } else {
                Spacer()
                Text(placeholderMessage)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            footer
        }
        .padding(.horizontal, 4)
        .navigationTitle("Hole \(model.engine.currentHoleNumber)")
    }

    private var header: some View {
        HStack(spacing: 4) {
            if let par = model.engine.currentHole?.par {
                Text("Par \(par)")
            }
            Spacer()
            Text("\(model.engine.currentHoleScore?.strokes ?? 0)")
                .monospacedDigit()
            Image(systemName: "figure.golf")
            Circle()
                .fill(qualityColour)
                .frame(width: 6, height: 6)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var footer: some View {
        if let suggestion = model.suggestedClub {
            Text("\(suggestion.club.abbreviation) · \(DistanceFormatter.whole(suggestion.average, in: model.unit))\(model.unit.shortLabel) avg")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if !model.workout.isRunning {
            // Worth saying out loud: without the workout session the watch will stop
            // updating the moment the wrist drops.
            Label("Background tracking off", systemImage: "exclamationmark.triangle")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        }
    }

    private func edge(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(DistanceFormatter.whole(value, in: model.unit))
                .font(.headline)
                .monospacedDigit()
        }
    }

    private var placeholderMessage: String {
        if model.location.currentLocation == nil { return "Finding GPS…" }
        return "No green marked for this hole"
    }

    private var qualityColour: Color {
        switch model.location.quality {
        case .none, .poor: return .red
        case .fair: return .orange
        case .good, .excellent: return .green
        }
    }
}
