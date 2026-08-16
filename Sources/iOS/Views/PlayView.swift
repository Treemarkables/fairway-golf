import SwiftUI

/// The phone's on-course screen. The watch is the primary instrument during a round —
/// this exists for starting and finishing, for the map, and for the times the phone is
/// already in your hand.
struct PlayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if model.engine.isActive {
                    activeRound
                } else {
                    startRound
                }
            }
            .navigationTitle(model.engine.isActive ? "Hole \(model.engine.currentHoleNumber)" : "Play")
        }
    }

    // MARK: - Before the round

    private var startRound: some View {
        List {
            if model.store.courses.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No courses yet", systemImage: "map")
                    } description: {
                        Text("Add a course on the Courses tab — import one from OpenStreetMap, or mark the greens yourself as you play.")
                    }
                }
            } else {
                Section("Start a round") {
                    ForEach(model.store.courses) { course in
                        Button {
                            model.startRound(on: course)
                        } label: {
                            CourseRow(course: course)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                LabeledContent("Apple Watch") {
                    Text(model.connectivity.isReachable ? "Connected" : "Not reachable")
                        .foregroundStyle(model.connectivity.isReachable ? .green : .secondary)
                }
                Button("Send courses to watch") { model.pushLibraryToWatch() }
                    .disabled(model.store.courses.isEmpty)
            } footer: {
                Text("The watch keeps its own copy of your courses and bag so it can run a round without the phone.")
            }
        }
    }

    // MARK: - During the round

    private var activeRound: some View {
        VStack(spacing: 0) {
            HoleMapView()
                .frame(maxHeight: .infinity)

            distancePanel
                .padding()
                .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GPSBadge(quality: model.location.quality)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add penalty stroke") { model.engine.addPenaltyStroke() }
                    Button("Undo last shot") { model.engine.undoLastShot() }
                    Divider()
                    NavigationLink("Scorecard") { ScorecardView() }
                    Button("Finish round", role: .destructive) { model.finishRound() }
                    Button("Abandon round", role: .destructive) { model.abandonRound() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var distancePanel: some View {
        VStack(spacing: 12) {
            if let distances = model.currentDistances {
                DistanceReadout(distances: distances, unit: model.unit)
            } else if model.location.currentLocation == nil {
                Label("Waiting for GPS", systemImage: "location.slash")
                    .foregroundStyle(.secondary)
            } else {
                Label("No green marked for this hole", systemImage: "flag.slash")
                    .foregroundStyle(.secondary)
            }

            if let suggestion = model.suggestedClub {
                Text("Your \(suggestion.club.name) averages \(DistanceFormatter.labelled(suggestion.average, in: model.unit))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    model.engine.previousHole()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(model.engine.currentHoleNumber <= (model.engine.holeNumbers.first ?? 1))

                Spacer()

                Text("\(model.engine.currentHoleScore?.strokes ?? 0) strokes")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    model.advanceHole()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(model.engine.currentHoleNumber >= (model.engine.holeNumbers.last ?? 18))
            }
            .buttonStyle(.bordered)

            NavigationLink {
                ShotEntryView()
            } label: {
                Label("Log a shot", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.location.currentLocation == nil)
        }
    }
}

/// The front / centre / back block. Centre is the number you actually play to, so it
/// gets the size; front and back frame it.
struct DistanceReadout: View {
    var distances: GreenDistances
    var unit: DistanceUnit

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            edge("Front", distances.front)
            Spacer()
            VStack(spacing: 0) {
                Text(DistanceFormatter.whole(distances.center, in: unit))
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("centre \(unit.shortLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            edge("Back", distances.back)
        }
    }

    private func edge(_ title: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text(DistanceFormatter.whole(value, in: unit))
                .font(.title2.weight(.medium))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct GPSBadge: View {
    var quality: GPSQuality

    var body: some View {
        Label(quality.label, systemImage: "location.fill")
            .font(.caption)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch quality {
        case .none, .poor: return .red
        case .fair: return .orange
        case .good, .excellent: return .green
        }
    }
}

struct CourseRow: View {
    var course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.name)
                .font(.headline)
            HStack(spacing: 6) {
                if let locality = course.locality {
                    Text(locality)
                }
                Text("\(course.holes.count) holes · par \(course.par)")
                if !course.isFullyMapped {
                    Text("· \(course.mappedHoleCount) greens marked")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
