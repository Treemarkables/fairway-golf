import Foundation

/// Tiny JSON-file persistence layer. There is no server and no database in this app —
/// courses, rounds and the bag are small enough that whole-file reads and writes are
/// simpler and more robust than anything else, and they work identically on the watch.
struct FileStore {
    enum StoreError: Error {
        case directoryUnavailable
    }

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(folderName: String = "Fairway") throws {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw StoreError.directoryUnavailable
        }
        directory = base.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.withoutEscapingSlashes]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    private func url(for name: String) -> URL {
        directory.appendingPathComponent("\(name).json", isDirectory: false)
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let fileURL = url(for: name)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    /// Writes atomically so a crash mid-round can't leave a half-written scorecard.
    @discardableResult
    func save<T: Encodable>(_ value: T, to name: String) -> Bool {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url(for: name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }
}
