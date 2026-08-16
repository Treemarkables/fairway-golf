import Foundation
import Observation
import SwiftUI

/// Wires the shared services together for the phone and owns the round lifecycle.
/// The watch has its own, smaller equivalent in `WatchModel`.
@Observable
@MainActor
final class AppModel {

    let store = DataStore()
    let location = LocationService()
    let engine = RoundEngine()
    let connectivity = ConnectivityService()

    /// Set when a round from a previous launch is found on disk, so the UI can offer
    /// to pick it back up instead of silently discarding a card.
    var recoverableRound: Round?

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

        // The watch is the authority while it's the device on your wrist mid-round.
        connectivity.onRoundReceived = { [weak self] payload in
            guard let self else { return }
            if payload.isFinished {
                self.store.saveFinished(payload.round)
                if self.engine.round?.id == payload.round.id { self.endLocalRound() }
            } else {
                self.engine.resume(round: payload.round, course: payload.course)
                self.store.saveInProgress(payload.round)
            }
        }

        connectivity.onLibraryRequested = { [weak self] in self?.pushLibraryToWatch() }
        connectivity.activate()

        recoverableRound = store.loadInProgressRound()
    }

    // MARK: - Round lifecycle

    func startRound(on course: Course) {
        location.requestAuthorization()
        location.startTracking()
        engine.start(course: course)
        pushLibraryToWatch()
    }

    func resumeRecoverableRound() {
        guard let round = recoverableRound,
              let course = store.course(withID: round.courseID) else { return }
        location.requestAuthorization()
        location.startTracking()
        engine.resume(round: round, course: course)
        recoverableRound = nil
    }

    func discardRecoverableRound() {
        store.clearInProgressRound()
        recoverableRound = nil
    }

    func finishRound() {
        guard let finished = engine.finish(
            location: location.currentLocation,
            accuracy: location.horizontalAccuracy
        ) else { return }
        store.saveFinished(finished)
        endLocalRound()
    }

    /// Abandons the card entirely — used when a round was started by mistake.
    func abandonRound() {
        store.clearInProgressRound()
        endLocalRound()
    }

    private func endLocalRound() {
        engine.discard()
        location.stopTracking()
    }

    // MARK: - Play

    func logShot(club: Club?) {
        guard let point = location.currentLocation else { return }
        engine.logShot(club: club, at: point, accuracy: location.horizontalAccuracy)
    }

    func advanceHole() {
        engine.nextHole(
            closingAt: location.currentLocation,
            accuracy: location.horizontalAccuracy
        )
    }

    var currentDistances: GreenDistances? {
        guard let point = location.currentLocation else { return nil }
        return engine.distances(from: point)
    }

    /// The club this player would normally pull for the distance to the centre of the
    /// green, based on their own logged shots. `nil` until there is enough history.
    var suggestedClub: ClubStatistics? {
        guard let distances = currentDistances else { return nil }
        let stats = store.clubStatistics.filter(\.isReliable)
        guard !stats.isEmpty else { return nil }
        return ClubStatsEngine.recommendedClub(for: distances.center, statistics: stats)
    }

    // MARK: - Sync

    func pushLibraryToWatch() {
        connectivity.sendLibrary(
            courses: store.courses,
            bag: store.bag,
            settings: store.settings
        )
    }

    var unit: DistanceUnit { store.settings.distanceUnit }
}
