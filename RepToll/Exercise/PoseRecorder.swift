import Foundation
import RepTollKit

/// Saves every analyzed frame of a session as JSON so detector thresholds can be tuned and
/// regression-tested against real movement. Opt-in from Settings; files stay in the app's Documents.
final class PoseRecorder {
    struct Recording: Codable {
        var exercise: Exercise
        var recordedAt: Date
        var frames: [PoseFrame]
    }

    static var directory: URL {
        URL.documentsDirectory.appending(path: "PoseRecordings", directoryHint: .isDirectory)
    }

    static func recordings() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    private var recording: Recording
    // Cap at ~10 minutes at 30 fps so a forgotten session can't fill the disk.
    private let maxFrames = 18_000

    init(exercise: Exercise) {
        recording = Recording(exercise: exercise, recordedAt: .now, frames: [])
    }

    func append(_ frame: PoseFrame) {
        guard recording.frames.count < maxFrames else { return }
        recording.frames.append(frame)
    }

    func save() {
        guard !recording.frames.isEmpty else { return }
        let stamp = recording.recordedAt.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let url = Self.directory.appending(path: "\(recording.exercise.rawValue)-\(stamp).json")
        do {
            try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(recording).write(to: url, options: .atomic)
        } catch {
            print("PoseRecorder: couldn't save \(url.lastPathComponent): \(error)")
        }
    }
}
