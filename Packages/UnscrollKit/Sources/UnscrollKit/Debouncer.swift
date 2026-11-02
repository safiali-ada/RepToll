import Foundation

/// Majority vote over a short time window so single noisy frames can't flip the exercise state.
/// Port of Pushscroll's `Ca/b`: a 250 ms window, the winning state needs 60% of the frames
/// expected in that window, and frames whose processing exceeds half the window are skipped.
public struct StateDebouncer<State: Hashable & Sendable>: Sendable {
    public let window: TimeInterval
    public let majority: Double
    public private(set) var current: State
    /// The state before the most recent `update`.
    public private(set) var previous: State
    private var samples: [(state: State, duration: TimeInterval)] = []

    public init(initial: State, window: TimeInterval = 0.25, majority: Double = 0.6) {
        self.current = initial
        self.previous = initial
        self.window = window
        self.majority = majority
    }

    /// Feeds one frame. Returns nil when the frame was skipped, otherwise whether the debounced state changed.
    @discardableResult
    public mutating func update(_ state: State, frameDuration: TimeInterval, processingTime: TimeInterval = 0) -> Bool? {
        guard processingTime <= window / 2, frameDuration > 0 else { return nil }
        samples.append((state, frameDuration))

        // Keep only the newest samples that fit in the window.
        var total: TimeInterval = 0
        var firstKept = 0
        for index in samples.indices.reversed() {
            total += samples[index].duration
            if total > window {
                firstKept = index + 1
                break
            }
        }
        if firstKept > 0 { samples.removeFirst(firstKept) }

        var next = current
        if !samples.isEmpty {
            let averageDuration = samples.reduce(0) { $0 + $1.duration } / Double(samples.count)
            let expectedFrames = window / averageDuration
            var counts: [State: Int] = [:]
            for sample in samples { counts[sample.state, default: 0] += 1 }
            if let winner = counts.max(by: { $0.value < $1.value }),
               Double(winner.value) >= majority * expectedFrames {
                next = winner.key
            }
        }

        previous = current
        current = next
        return previous != current
    }
}
