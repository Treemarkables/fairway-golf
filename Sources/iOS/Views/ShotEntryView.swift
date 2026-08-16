import SwiftUI

/// Pick the club you're about to hit. The shot is stamped at your current position;
/// where it finishes is filled in by the next shot you log, or by walking to the next hole.
struct ShotEntryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if !model.location.quality.isUsableForShotLogging {
                Section {
                    Label(
                        "GPS is weak right now. The shot will still be recorded, but it'll be left out of your club averages.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.orange)
                }
            }

            Section("Club") {
                ForEach(model.store.bag.inBag) { club in
                    Button {
                        model.logShot(club: club)
                        dismiss()
                    } label: {
                        HStack {
                            Text(club.abbreviation)
                                .font(.headline.monospaced())
                                .frame(width: 40, alignment: .leading)
                            Text(club.name)
                            Spacer()
                            if let stat = statistics(for: club) {
                                Text(DistanceFormatter.labelled(stat.average, in: model.unit))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("Log without a club") {
                    model.logShot(club: nil)
                    dismiss()
                }
            } footer: {
                Text("Counts on the card but not in any club's averages.")
            }
        }
        .navigationTitle("Log a shot")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statistics(for club: Club) -> ClubStatistics? {
        model.store.clubStatistics.first { $0.club.id == club.id }
    }
}
