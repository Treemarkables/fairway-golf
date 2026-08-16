import Foundation
import Observation

/// The app's whole persistent state: courses, finished rounds, the bag, settings, and
/// any round interrupted mid-play. Backed by JSON files — see `FileStore` for why.
@Observable
final class DataStore {

    private enum Key {
        static let courses = "courses"
        static let rounds = "rounds"
        static let bag = "bag"
        static let settings = "settings"
        static let inProgressRound = "round-in-progress"
    }

    private(set) var courses: [Course] = []
    private(set) var rounds: [Round] = []
    private(set) var bag: Bag = .standard
    /// Bound directly by the settings screen, which calls `persistSettings()` on change.
    /// Deliberately has no `didSet` — `@Observable` does not allow property observers
    /// on tracked properties.
    var settings: AppSettings = .default

    @ObservationIgnored private let store: FileStore?

    init() {
        store = try? FileStore()
        load()
    }

    private func load() {
        guard let store else { return }
        courses = store.load([Course].self, from: Key.courses) ?? []
        rounds = store.load([Round].self, from: Key.rounds) ?? []
        bag = store.load(Bag.self, from: Key.bag) ?? .standard
        settings = store.load(AppSettings.self, from: Key.settings) ?? .default
    }

    // MARK: - Courses

    func course(withID id: UUID) -> Course? {
        courses.first { $0.id == id }
    }

    /// Inserts or replaces by id, keeping the list sorted by name.
    func upsert(_ course: Course) {
        var updated = course
        updated.updatedAt = Date()
        if let index = courses.firstIndex(where: { $0.id == course.id }) {
            courses[index] = updated
        } else {
            courses.append(updated)
        }
        courses.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        store?.save(courses, to: Key.courses)
    }

    func deleteCourse(id: UUID) {
        courses.removeAll { $0.id == id }
        store?.save(courses, to: Key.courses)
    }

    // MARK: - Rounds

    /// Newest first — the order every history screen wants.
    var roundsNewestFirst: [Round] {
        rounds.sorted { $0.startedAt > $1.startedAt }
    }

    func saveFinished(_ round: Round) {
        if let index = rounds.firstIndex(where: { $0.id == round.id }) {
            rounds[index] = round
        } else {
            rounds.append(round)
        }
        store?.save(rounds, to: Key.rounds)
        clearInProgressRound()
    }

    func deleteRound(id: UUID) {
        rounds.removeAll { $0.id == id }
        store?.save(rounds, to: Key.rounds)
    }

    // MARK: - Round recovery

    /// Written continuously during play so a crash, a flat phone, or a force-quit
    /// between the 11th and 12th doesn't cost the card.
    func saveInProgress(_ round: Round) {
        store?.save(round, to: Key.inProgressRound)
    }

    func loadInProgressRound() -> Round? {
        store?.load(Round.self, from: Key.inProgressRound)
    }

    func clearInProgressRound() {
        store?.delete(Key.inProgressRound)
    }

    // MARK: - Settings

    func persistSettings() {
        store?.save(settings, to: Key.settings)
    }

    // MARK: - Bag

    func updateBag(_ bag: Bag) {
        self.bag = bag
        store?.save(bag, to: Key.bag)
    }

    func club(withID id: UUID) -> Club? {
        bag.club(withID: id)
    }

    // MARK: - Derived

    var clubStatistics: [ClubStatistics] {
        ClubStatsEngine.statistics(rounds: rounds, bag: bag, settings: settings)
    }

    var clubGaps: [ClubGap] {
        ClubStatsEngine.gaps(from: clubStatistics)
    }

    /// Replaces the local library wholesale — used when the watch receives a fresh
    /// copy of the courses and bag from the phone.
    func replaceLibrary(courses: [Course], bag: Bag, settings: AppSettings) {
        self.courses = courses.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        self.bag = bag
        self.settings = settings
        store?.save(self.courses, to: Key.courses)
        store?.save(bag, to: Key.bag)
        store?.save(settings, to: Key.settings)
    }

    /// Merges rounds arriving from the other device, newest copy winning on conflict.
    func mergeRounds(_ incoming: [Round]) {
        for round in incoming {
            if let index = rounds.firstIndex(where: { $0.id == round.id }) {
                let existing = rounds[index]
                let existingStamp = existing.finishedAt ?? existing.startedAt
                let incomingStamp = round.finishedAt ?? round.startedAt
                if incomingStamp >= existingStamp { rounds[index] = round }
            } else {
                rounds.append(round)
            }
        }
        store?.save(rounds, to: Key.rounds)
    }
}
