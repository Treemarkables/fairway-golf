import Foundation
import Observation
import SwiftUI
import WatchKit

/// The watch's counterpart to `AppModel`. It runs the same `RoundEngine` against the
/// same models, so a round can be driven entirely from the wrist with the phone in the bag.
@Observable
@MainActor
final class WatchModel {

    let store = DataStore()
    let location = LocationService()
    let engine = RoundEngine()
    let connectivity = ConnectivityService()
    let workout = WorkoutManager()

    init() {
        engine.bagLookup = { [weak self] id in self?.store.club(withID: id) }

        engine.onChange = { [weak self] round in
            guard let self else { return }
            self.store.saveInProgress(round)
            if let course = self.engine.course {
                self.connectivity.sendRound(
                    round,
                    course: course,
                    currentHoleNumber: self.engine.currentHoleNumber,
                    isFinished: round.isComplete
                )
            }
        }

        location.onLocationUpdate = { [weak self] point, accuracy, date in
            self?.engine.recordTrackPoint(point, accuracy: accuracy, at: date)
        }

        connectivity.onLibraryReceived = { [weak self] payload in
            self?.store.replaceLibrary(
                courses: payload.courses,
                bag: payload.bag,
                settings: payload.settings
            )
        }

        // If the phone started the round, pick it up here rather than starting a second one.
        connectivity.onRoundReceived = { [weak self] payload in
            guard let self else { return }
            if payload.isFinished {
                self.store.saveFinished(payload.round)
                self.stopSensors()
                self.engine.discard()
            } else if self.engine.round?.id != payload.round.id {
                self.engine.resume(round: payload.round, course: payload.course)
                self.startSensors()
            }
        }

        connectivity.activate()
        // The watch's library can be stale after a phone-side edit; ask on launch.
        connectivity.requestLibrary()
    }

    // MARK: - Round lifecycle

    func startRound(on course: Course) {
        Task {
            await workout.requestAuthorization()
            location.requestAuthorization()
            startSensors()
            engine.start(course: course)
        }
    }

    func finishRound() {
        guard let finished = engine.finish(
            location: location.currentLocation,
            accuracy: location.horizontalAccuracy
        ) else { return }
        store.saveFinished(finished)
        stopSensors()
        engine.discard()
    }

    func abandonRound() {
        store.clearInProgressRound()
        stopSensors()
        engine.discard()
    }

    private func startSensors() {
        location.startTracking()
        // Order matters: the workout session is what keeps location alive once the
        // wrist drops, so it must be running before the player walks off.
        workout.start()
    }

    private func stopSensors() {
        workout.end()
        location.stopTracking()
    }

    // MARK: - Play

    func logShot(club: Club?) {
        guard let point = location.currentLocation else { return }
        engine.logShot(club: club, at: point, accuracy: location.horizontalAccuracy)
        WKInterfaceDevice.current().play(.success)
    }

    func advanceHole() {
        engine.nextHole(
            closingAt: location.currentLocation,
            accuracy: location.horizontalAccuracy
        )
        WKInterfaceDevice.current().play(.click)
    }

    var currentDistances: GreenDistances? {
        guard let point = location.currentLocation else { return nil }
        return engine.distances(from: point)
    }

    var suggestedClub: ClubStatistics? {
        guard let distances = currentDistances else { return nil }
        let stats = store.clubStatistics.filter(\.isReliable)
        guard !stats.isEmpty else { return nil }
        return ClubStatsEngine.recommendedClub(for: distances.center, statistics: stats)
    }

    var unit: DistanceUnit { store.settings.distanceUnit }
}
