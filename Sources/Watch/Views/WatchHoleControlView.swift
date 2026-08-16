import SwiftUI

/// Hole navigation and the card. Moving to the next hole is what closes out the last
/// shot — the position you're standing in as you walk off becomes where that shot
/// finished, which is what makes the club distance real.
struct WatchHoleControlView: View {
    @Environment(WatchModel.self) private var model
    @State private var isConfirmingFinish = false

    var body: some View {
        List {
            Section {
                HStack {
                    Button {
                        model.engine.previousHole()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(model.engine.currentHoleNumber <= (model.engine.holeNumbers.first ?? 1))

                    Spacer()
                    Text("\(model.engine.currentHoleNumber)")
                        .font(.title2.monospacedDigit())
                    Spacer()

                    Button {
                        model.advanceHole()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(model.engine.currentHoleNumber >= (model.engine.holeNumbers.last ?? 18))
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Hole")
            }

            Section("This hole") {
                Stepper(
                    "Putts \(model.engine.currentHoleScore?.putts ?? 0)",
                    value: Binding(
                        get: { model.engine.currentHoleScore?.putts ?? 0 },
                        set: { model.engine.setPutts($0) }
                    ),
                    in: 0...10
                )
                Button("Penalty stroke") { model.engine.addPenaltyStroke() }
            }

            Section("Round") {
                if let round = model.engine.round {
                    LabeledContent("Strokes", value: "\(round.totalStrokes)")
                    LabeledContent("To par", value: round.scoreToParDisplay)
                }
                Button("Finish round") { isConfirmingFinish = true }
                    .foregroundStyle(.green)
                Button("Abandon", role: .destructive) { model.abandonRound() }
            }
        }
        .navigationTitle("Card")
        .confirmationDialog(
            "Finish this round?",
            isPresented: $isConfirmingFinish,
            titleVisibility: .visible
        ) {
            Button("Finish") { model.finishRound() }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("The card is saved and every shot feeds your club averages.")
        }
    }
}
