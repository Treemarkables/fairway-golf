import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            PlayView()
                .tabItem { Label("Play", systemImage: "flag.circle") }

            CourseListView()
                .tabItem { Label("Courses", systemImage: "map") }

            StatsView()
                .tabItem { Label("Clubs", systemImage: "chart.bar") }

            RoundHistoryView()
                .tabItem { Label("Rounds", systemImage: "list.bullet.rectangle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .alert(
            "Unfinished round",
            isPresented: .constant(model.recoverableRound != nil && !model.engine.isActive)
        ) {
            Button("Resume") { model.resumeRecoverableRound() }
            Button("Discard", role: .destructive) { model.discardRecoverableRound() }
        } message: {
            if let round = model.recoverableRound {
                Text("A round at \(round.courseName) was left open. Pick it back up?")
            }
        }
    }
}
