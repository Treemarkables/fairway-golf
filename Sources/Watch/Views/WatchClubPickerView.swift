import SwiftUI

/// Swipe up from the distance screen, spin the Digital Crown to your club, tap.
/// One tap is the whole interaction — anything longer and you won't do it mid-round.
///
/// The list is ordered longest club first (the bag's `sortOrder`), and each row carries
/// your own average for that club, so the pick doubles as a sanity check against the
/// number on the previous screen.
struct WatchClubPickerView: View {
    @Environment(WatchModel.self) private var model

    private var suggestedID: UUID? { model.suggestedClub?.club.id }

    var body: some View {
        List {
            Section {
                ForEach(model.store.bag.inBag) { club in
                    Button {
                        model.logShot(club: club)
                    } label: {
                        HStack {
                            Text(club.abbreviation)
                                .font(.headline.monospaced())
                                .frame(width: 34, alignment: .leading)

                            if club.id == suggestedID {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.yellow)
                            }

                            Spacer()

                            if let average = average(for: club) {
                                Text(DistanceFormatter.whole(average, in: model.unit))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Log a shot")
            }

            Section {
                Button("No club") { model.logShot(club: nil) }
                Button("Undo last shot", role: .destructive) { model.engine.undoLastShot() }
            }
        }
        .navigationTitle("Clubs")
        .disabled(model.location.currentLocation == nil)
        .overlay {
            if model.location.currentLocation == nil {
                Text("Waiting for GPS")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func average(for club: Club) -> Double? {
        model.store.clubStatistics.first { $0.club.id == club.id }?.average
    }
}
