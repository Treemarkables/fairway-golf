import Foundation
import HealthKit
import Observation

/// Runs an `HKWorkoutSession` for the duration of a round.
///
/// This is the single most important piece of the watch app, and it is not about
/// fitness tracking. watchOS suspends a foreground app within seconds of the wrist
/// dropping; an *active workout session* is what grants the app runtime and keeps
/// CoreLocation delivering fixes for four and a half hours. Without it, distances
/// freeze the moment you put your arm down and walk to your ball.
///
/// The side benefit is that the round shows up in Fitness as a golf workout with
/// distance and calories, which is what most people want anyway.
@Observable
final class WorkoutManager: NSObject {

    private let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    private(set) var isRunning = false
    private(set) var authorizationDenied = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var activeEnergyBurned: Double = 0
    private(set) var distanceWalked: Double = 0

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for the minimum that a workout session needs: permission to write the
    /// workout itself, and to read back the live metrics shown during the round.
    func requestAuthorization() async {
        guard isAvailable else { return }

        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate)
        ]

        do {
            try await healthStore.requestAuthorization(toShare: share, read: read)
            authorizationDenied = false
        } catch {
            authorizationDenied = true
        }
    }

    func start() {
        guard isAvailable, !isRunning else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .golf
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self

            let start = Date()
            session.startActivity(with: start)
            builder.beginCollection(withStart: start) { _, _ in }

            self.session = session
            self.builder = builder
            isRunning = true
        } catch {
            // A failed session isn't fatal — the round still records, it just won't
            // survive the wrist going down. The UI surfaces this via `isRunning`.
            isRunning = false
        }
    }

    func end() {
        guard let session, let builder else { return }
        let finish = Date()
        session.end()
        builder.endCollection(withEnd: finish) { [weak self] _, _ in
            builder.finishWorkout { _, _ in
                Task { @MainActor in
                    self?.session = nil
                    self?.builder = nil
                    self?.isRunning = false
                }
            }
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.isRunning = (toState == .running)
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRunning = false
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType)
            else { continue }

            Task { @MainActor in
                switch quantityType {
                case HKQuantityType(.activeEnergyBurned):
                    self.activeEnergyBurned = statistics.sumQuantity()?
                        .doubleValue(for: .kilocalorie()) ?? 0
                case HKQuantityType(.distanceWalkingRunning):
                    self.distanceWalked = statistics.sumQuantity()?
                        .doubleValue(for: .meter()) ?? 0
                default:
                    break
                }
                self.elapsed = workoutBuilder.elapsedTime
            }
        }
    }
}
