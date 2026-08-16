import SwiftUI

struct CourseEditorView: View {
    @Environment(AppModel.self) private var model
    @State private var course: Course

    init(course: Course) {
        _course = State(initialValue: course)
    }

    var body: some View {
        List {
            Section {
                TextField("Name", text: $course.name)
                TextField("Town or region", text: Binding(
                    get: { course.locality ?? "" },
                    set: { course.locality = $0.isEmpty ? nil : $0 }
                ))
                LabeledContent("Source", value: course.source.displayName)
            }

            Section {
                ForEach($course.holes) { $hole in
                    NavigationLink {
                        HoleEditorView(hole: $hole)
                    } label: {
                        HoleEditorRow(hole: hole)
                    }
                }
            } header: {
                Text("Holes")
            } footer: {
                Text("\(course.mappedHoleCount) of \(course.holes.count) greens marked. A hole with no green marked shows no distance.")
            }
        }
        .navigationTitle(course.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    model.store.upsert(course)
                    model.pushLibraryToWatch()
                }
            }
        }
    }
}

struct HoleEditorRow: View {
    var hole: Hole

    var body: some View {
        HStack {
            Text("\(hole.number)")
                .font(.body.monospacedDigit())
                .frame(width: 28, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("Par \(hole.par)")
                if let length = hole.nominalLength {
                    Text("\(Int(length.rounded())) m tee to green")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: hole.hasGreen ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(hole.hasGreen ? .green : .secondary)
        }
    }
}

/// Marking a green by hand. Two ways to do it:
///
/// **Drop a pin** — stand anywhere on the green and capture one point. Fast, and gives
/// a single distance rather than front/centre/back.
///
/// **Walk the edge** — walk the perimeter tapping Add Point every few paces. Four or
/// five points around the outline is plenty, and it's what makes real front and back
/// numbers possible.
struct HoleEditorView: View {
    @Environment(AppModel.self) private var model
    @Binding var hole: Hole

    var body: some View {
        List {
            Section("Hole") {
                Stepper("Par \(hole.par)", value: $hole.par, in: 3...6)
                Stepper(
                    "Stroke index \(hole.strokeIndex.map(String.init) ?? "—")",
                    value: Binding(
                        get: { hole.strokeIndex ?? 0 },
                        set: { hole.strokeIndex = $0 == 0 ? nil : $0 }
                    ),
                    in: 0...18
                )
            }

            Section {
                if let green = hole.green, !green.isEmpty {
                    LabeledContent(
                        "Green",
                        value: green.isPinOnly ? "Single pin" : "\(green.polygon.count) points"
                    )
                } else {
                    Text("No green marked")
                        .foregroundStyle(.secondary)
                }

                Button {
                    capture(replacing: true)
                } label: {
                    Label("Drop a pin here", systemImage: "mappin.and.ellipse")
                }

                Button {
                    capture(replacing: false)
                } label: {
                    Label("Add point to outline", systemImage: "plus.circle")
                }

                if hole.green != nil {
                    Button(role: .destructive) {
                        hole.green = nil
                    } label: {
                        Label("Clear green", systemImage: "trash")
                    }
                }
            } header: {
                Text("Green")
            } footer: {
                Text("Walk the edge of the green and tap Add Point four or five times to get true front and back numbers. A single pin gives one distance only.")
            }

            Section {
                Button {
                    guard let point = model.location.currentLocation else { return }
                    hole.tees = [TeeBox(name: "Tee", point: point)]
                } label: {
                    Label("Set tee here", systemImage: "figure.golf")
                }
            } header: {
                Text("Tee")
            } footer: {
                GPSStatusFooter()
            }
        }
        .navigationTitle("Hole \(hole.number)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Marking greens needs a live fix even outside a round.
            model.location.requestAuthorization()
            model.location.startTracking()
        }
        .onDisappear {
            if !model.engine.isActive { model.location.stopTracking() }
        }
    }

    private func capture(replacing: Bool) {
        guard let point = model.location.currentLocation else { return }
        if replacing || hole.green == nil {
            hole.green = Green(pin: point)
        } else {
            hole.green?.polygon.append(point)
        }
    }
}

struct GPSStatusFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let location = model.location.currentLocation {
            Text("GPS: \(model.location.quality.label), ±\(Int(model.location.horizontalAccuracy.rounded())) m at \(String(format: "%.5f", location.latitude)), \(String(format: "%.5f", location.longitude))")
        } else {
            Text("Waiting for a GPS fix — this needs to be done outdoors, standing on the green.")
        }
    }
}
