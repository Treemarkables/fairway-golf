import SwiftUI

struct WatchRootView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            if model.engine.isActive {
                // Vertical paging is the watchOS idiom for "same context, different
                // panel" — swipe up for clubs, down for the card, no navigation needed.
                TabView {
                    WatchDistanceView()
                    WatchClubPickerView()
                    WatchHoleControlView()
                }
                .tabViewStyle(.verticalPage)
            } else {
                WatchStartRoundView()
            }
        }
    }
}

struct WatchStartRoundView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
            if model.store.courses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No courses on the watch")
                        .font(.headline)
                    Text("Open Fairway on your iPhone and send your courses across.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Ask iPhone again") { model.connectivity.requestLibrary() }
                }
            } else {
                Section("Start a round") {
                    ForEach(model.store.courses) { course in
                        Button {
                            model.startRound(on: course)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text("\(course.mappedHoleCount)/\(course.holes.count) greens")
                                    .font(.caption2)
                                    .foregroundStyle(course.isFullyMapped ? .secondary : .orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fairway")
    }
}
