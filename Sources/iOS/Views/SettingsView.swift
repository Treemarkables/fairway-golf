import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Bind to the store directly — `model.store` is a constant reference, so the
        // bindable wrapper has to sit on the observable object that owns `settings`.
        @Bindable var store = model.store

        NavigationStack {
            List {
                Section("Units") {
                    Picker("Distances in", selection: $store.settings.distanceUnit) {
                        ForEach(DistanceUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section {
                    NavigationLink {
                        BagEditorView()
                    } label: {
                        Label("My bag", systemImage: "bag")
                    }
                }

                Section {
                    Toggle("Ignore outlier shots", isOn: $store.settings.trimOutliers)

                    VStack(alignment: .leading) {
                        Text("Minimum full swing: \(Int(store.settings.minimumFullSwingDistance)) m")
                        Slider(
                            value: $store.settings.minimumFullSwingDistance,
                            in: 10...80,
                            step: 5
                        )
                    }

                    VStack(alignment: .leading) {
                        Text("Discard shots worse than ±\(Int(store.settings.statsAccuracyCeiling)) m GPS")
                        Slider(
                            value: $store.settings.statsAccuracyCeiling,
                            in: 5...40,
                            step: 1
                        )
                    }
                } header: {
                    Text("Club statistics")
                } footer: {
                    Text("Outlier trimming drops the longest and shortest 10% of each club's shots before averaging, so one shank doesn't move your 7 iron number. Short shots are excluded for every club except wedges, where partial shots are the point.")
                }

                Section {
                    Toggle("Keep watch screen on", isOn: $store.settings.keepWatchScreenActive)
                    LabeledContent("Watch") {
                        Text(model.connectivity.isReachable ? "Connected" : "Not reachable")
                            .foregroundStyle(model.connectivity.isReachable ? .green : .secondary)
                    }
                    Button("Send courses and bag to watch") { model.pushLibraryToWatch() }
                } header: {
                    Text("Apple Watch")
                } footer: {
                    Text("A round runs a golf workout on the watch. That's what keeps GPS alive between holes — without it watchOS suspends the app and distances stop updating. Budget roughly a third of the watch battery for eighteen holes.")
                }

                Section {
                    LabeledContent("Courses", value: "\(model.store.courses.count)")
                    LabeledContent("Rounds", value: "\(model.store.rounds.count)")
                    LabeledContent("Shots logged", value: "\(model.store.rounds.reduce(0) { $0 + $1.allShots.count })")
                } header: {
                    Text("Library")
                } footer: {
                    Text("Everything is stored on this device. There is no account and no server.")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: store.settings) { _, _ in
                store.persistSettings()
                model.pushLibraryToWatch()
            }
        }
    }
}
