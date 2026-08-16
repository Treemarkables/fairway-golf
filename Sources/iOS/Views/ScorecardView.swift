import SwiftUI

/// The card for the round in play. Editable, because the honest truth is that a
/// shot or two per round gets logged wrong and it's easier to fix here than on the wrist.
struct ScorecardView: View {
    @Environment(AppModel.self) private var model

    private var round: Round? { model.engine.round }

    var body: some View {
        List {
            if let round {
                Section {
                    LabeledContent("Strokes", value: "\(round.totalStrokes)")
                    LabeledContent("To par", value: round.scoreToParDisplay)
                    LabeledContent("Putts", value: "\(round.totalPutts)")
                }

                Section("Holes") {
                    ForEach(round.holes) { hole in
                        HoleScoreRow(score: hole, isCurrent: hole.holeNumber == model.engine.currentHoleNumber)
                    }
                }

                Section("This hole") {
                    Stepper(
                        "Putts: \(model.engine.currentHoleScore?.putts ?? 0)",
                        value: Binding(
                            get: { model.engine.currentHoleScore?.putts ?? 0 },
                            set: { model.engine.setPutts($0) }
                        ),
                        in: 0...10
                    )
                    Stepper(
                        "Extra strokes: \(model.engine.currentHoleScore?.adjustment ?? 0)",
                        value: Binding(
                            get: { model.engine.currentHoleScore?.adjustment ?? 0 },
                            set: { model.engine.setAdjustment($0) }
                        ),
                        in: 0...10
                    )
                }
            } else {
                ContentUnavailableView("No round in play", systemImage: "list.bullet.rectangle")
            }
        }
        .navigationTitle("Scorecard")
    }
}

struct HoleScoreRow: View {
    var score: HoleScore
    var isCurrent: Bool = false

    var body: some View {
        HStack {
            Text("\(score.holeNumber)")
                .font(.body.monospacedDigit())
                .frame(width: 28, alignment: .leading)
                .fontWeight(isCurrent ? .bold : .regular)

            Text("Par \(score.par)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if score.isPlayed {
                Text(relativeLabel)
                    .font(.caption)
                    .foregroundStyle(colour)
                Text("\(score.strokes)")
                    .font(.body.monospacedDigit())
                    .frame(width: 28, alignment: .trailing)
            } else {
                Text("–")
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }

    private var relativeLabel: String {
        let value = score.scoreToPar
        if value == 0 { return "par" }
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private var colour: Color {
        switch score.scoreToPar {
        case ..<0: return .red
        case 0: return .secondary
        default: return .blue
        }
    }
}
