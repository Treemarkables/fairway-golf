import SwiftUI

struct RoundHistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if model.store.rounds.isEmpty {
                    ContentUnavailableView {
                        Label("No rounds yet", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Finished rounds land here, and every shot in them feeds your club averages.")
                    }
                }

                ForEach(model.store.roundsNewestFirst) { round in
                    NavigationLink {
                        RoundDetailView(round: round)
                    } label: {
                        RoundRow(round: round)
                    }
                }
                .onDelete { offsets in
                    let rounds = model.store.roundsNewestFirst
                    for index in offsets { model.store.deleteRound(id: rounds[index].id) }
                }
            }
            .navigationTitle("Rounds")
        }
    }
}

struct RoundRow: View {
    var round: Round

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName).font(.headline)
                Text(round.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(round.totalStrokes)")
                    .font(.title3.monospacedDigit())
                Text(round.scoreToParDisplay)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RoundDetailView: View {
    @Environment(AppModel.self) private var model
    var round: Round

    var body: some View {
        List {
            Section {
                LabeledContent("Strokes", value: "\(round.totalStrokes)")
                LabeledContent("To par", value: round.scoreToParDisplay)
                LabeledContent("Putts", value: "\(round.totalPutts)")
                LabeledContent("Holes played", value: "\(round.playedHoles.count)")
                if let finished = round.finishedAt {
                    LabeledContent(
                        "Duration",
                        value: (finished.timeIntervalSince(round.startedAt) / 3600)
                            .formatted(.number.precision(.fractionLength(1))) + " h"
                    )
                }
            }

            Section("Holes") {
                ForEach(round.holes) { hole in
                    HoleScoreRow(score: hole)
                }
            }

            Section("Shots") {
                ForEach(round.allShots) { shot in
                    HStack {
                        Text("\(shot.holeNumber)")
                            .font(.caption.monospacedDigit())
                            .frame(width: 24, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(clubName(for: shot))
                        Spacer()
                        if let distance = shot.measuredDistance {
                            Text(DistanceFormatter.labelled(distance, in: model.unit))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } else {
                            Text("not closed")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func clubName(for shot: Shot) -> String {
        guard let id = shot.clubID, let club = model.store.club(withID: id) else { return "No club" }
        return club.name
    }
}
