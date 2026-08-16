import Foundation
import Observation
import WatchConnectivity

/// What travels between phone and watch. Small enough to send whole — a course is a
/// few hundred coordinates, and a round is a few hundred more.
enum SyncPayload {
    /// Phone → watch. The courses and bag the watch needs to play a round on its own.
    struct Library: Codable, Sendable {
        var courses: [Course]
        var bag: Bag
        var settings: AppSettings
    }

    /// Either direction. Whoever is holding the round pushes it to the other device.
    struct RoundUpdate: Codable, Sendable {
        var round: Round
        var course: Course
        var currentHoleNumber: Int
        var isFinished: Bool
    }

    enum Kind: String, Codable, Sendable {
        case library
        case roundUpdate
        case requestLibrary
    }
}

/// Wraps `WCSession` for both platforms. Live messages when the counterpart is reachable,
/// queued `transferUserInfo` when it isn't — which is most of a round, since the phone
/// spends four hours in a bag pocket.
@Observable
final class ConnectivityService: NSObject, WCSessionDelegate {

    private(set) var isReachable = false
    private(set) var isPaired = false
    private(set) var lastSyncAt: Date?

    @ObservationIgnored var onLibraryReceived: ((SyncPayload.Library) -> Void)?
    @ObservationIgnored var onRoundReceived: ((SyncPayload.RoundUpdate) -> Void)?
    @ObservationIgnored var onLibraryRequested: (() -> Void)?

    @ObservationIgnored private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @ObservationIgnored private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: - Sending

    func sendLibrary(courses: [Course], bag: Bag, settings: AppSettings) {
        let payload = SyncPayload.Library(courses: courses, bag: bag, settings: settings)
        send(kind: .library, payload: payload)
    }

    func sendRound(_ round: Round, course: Course, currentHoleNumber: Int, isFinished: Bool) {
        let payload = SyncPayload.RoundUpdate(
            round: round,
            course: course,
            currentHoleNumber: currentHoleNumber,
            isFinished: isFinished
        )
        send(kind: .roundUpdate, payload: payload)
    }

    func requestLibrary() {
        send(kind: .requestLibrary, payload: EmptyPayload())
    }

    private struct EmptyPayload: Codable {}

    private func send<T: Encodable>(kind: SyncPayload.Kind, payload: T) {
        guard let session, session.activationState == .activated else { return }
        guard let data = try? encoder.encode(payload) else { return }
        let message: [String: Any] = ["kind": kind.rawValue, "payload": data]

        if session.isReachable {
            // No reply handler: this is fire-and-forget state mirroring, and the
            // errorHandler fallback keeps a dropped message from being lost.
            session.sendMessage(message, replyHandler: nil) { [weak self] _ in
                self?.queue(message)
            }
        } else {
            queue(message)
        }
    }

    /// `transferUserInfo` survives the counterpart being asleep, out of range, or
    /// rebooted — it delivers whenever the devices next see each other.
    private func queue(_ message: [String: Any]) {
        session?.transferUserInfo(message)
    }

    // MARK: - Receiving

    private func handle(_ message: [String: Any]) {
        guard
            let raw = message["kind"] as? String,
            let kind = SyncPayload.Kind(rawValue: raw)
        else { return }

        let data = message["payload"] as? Data

        Task { @MainActor in
            switch kind {
            case .library:
                guard let data,
                      let payload = try? self.decoder.decode(SyncPayload.Library.self, from: data)
                else { return }
                self.onLibraryReceived?(payload)
            case .roundUpdate:
                guard let data,
                      let payload = try? self.decoder.decode(SyncPayload.RoundUpdate.self, from: data)
                else { return }
                self.onRoundReceived?(payload)
            case .requestLibrary:
                self.onLibraryRequested?()
            }
            self.lastSyncAt = Date()
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidComplete state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(iOS)
            self.isPaired = session.isPaired && session.isWatchAppInstalled
            #else
            self.isPaired = state == .activated
            #endif
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Fires when the user pairs a different watch; reactivating rebinds the session.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
