import Foundation
import Testing
@testable import RepTollKit

/// Builds synthetic poses with exact joint angles, fed at 30 fps.
struct PoseFactory {
    var t: TimeInterval = 0
    let dt: TimeInterval = 1.0 / 30

    mutating func next(_ points: [Joint: SIMD3<Double>], confidence: Double = 0.9) -> PoseFrame {
        defer { t += dt }
        return PoseFrame(timestamp: t, processingTime: 0.02,
                         points: points.mapValues { PosePoint(position: $0, confidence: confidence) })
    }

    /// Both arms bent to `elbow` degrees (right arm can differ for asymmetry tests).
    static func pushup(elbow: Double, rightElbow: Double? = nil) -> [Joint: SIMD3<Double>] {
        func arm(_ x: Double, _ deg: Double) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
            let r = deg * .pi / 180
            let shoulder = SIMD3(x, 0, 0), elbowP = SIMD3(x + 0.3, 0, 0)
            return (shoulder, elbowP, elbowP + 0.3 * SIMD3(-cos(r), sin(r), 0))
        }
        let l = arm(-0.2, elbow), rt = arm(0.2, rightElbow ?? elbow)
        return [.leftShoulder: l.0, .leftElbow: l.1, .leftWrist: l.2,
                .rightShoulder: rt.0, .rightElbow: rt.1, .rightWrist: rt.2,
                .leftHip: [-0.15, 0, 1], .rightHip: [0.15, 0, 1]]
    }

    static func squat(knee: Double) -> [Joint: SIMD3<Double>] {
        func leg(_ x: Double) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
            let r = knee * .pi / 180
            let hip = SIMD3(x, 1, 0), kneeP = SIMD3(x, 0.5, 0)
            return (hip, kneeP, kneeP + 0.5 * SIMD3(0, cos(r), sin(r)))
        }
        let l = leg(-0.15), r = leg(0.15)
        return [.leftHip: l.0, .leftKnee: l.1, .leftAnkle: l.2,
                .rightHip: r.0, .rightKnee: r.1, .rightAnkle: r.2,
                .leftShoulder: [-0.2, 1.5, 0], .rightShoulder: [0.2, 1.5, 0]]
    }

    static func plank(hipLift: Double = 0) -> [Joint: SIMD3<Double>] {
        var p: [Joint: SIMD3<Double>] = [:]
        for (side, x) in [(0, -0.2), (1, 0.2)] {
            let shoulder = SIMD3(x, 0, 0)
            let elbow = SIMD3(x, -0.3, 0)
            let wrist = SIMD3(x, -0.3, 0.3)
            let hip = SIMD3(x, hipLift, 1)
            let knee = SIMD3(x, 0, 1.5)
            if side == 0 {
                p[.leftShoulder] = shoulder; p[.leftElbow] = elbow; p[.leftWrist] = wrist; p[.leftHip] = hip; p[.leftKnee] = knee
            } else {
                p[.rightShoulder] = shoulder; p[.rightElbow] = elbow; p[.rightWrist] = wrist; p[.rightHip] = hip; p[.rightKnee] = knee
            }
        }
        return p
    }
}

@Suite struct GeometryTests {
    @Test func rightAngle() throws {
        let a = try #require(Geometry.angle([1, 0, 0], [0, 0, 0], [0, 1, 0]))
        #expect(abs(a - 90) < 1e-9)
    }

    @Test func degenerateIsNil() {
        #expect(Geometry.angle([0, 0, 0], [0, 0, 0], [1, 0, 0]) == nil)
    }

    @Test func factoryProducesRequestedElbowAngle() throws {
        var f = PoseFactory()
        let frame = f.next(PoseFactory.pushup(elbow: 77))
        let a = try #require(Geometry.angle(frame, .leftShoulder, .leftElbow, .leftWrist))
        #expect(abs(a - 77) < 1e-6)
    }
}

/// Push-ups seen by a phone on the floor facing the user, at the ~16 fps the camera actually delivers.
@Suite struct PushupTests {
    static let dt = 1.0 / 16
    var t = 0.0

    /// `depth` 1 = top, 0.5 = chest near the floor. Hands planted at y 0.7, shoulders 0.2 apart.
    func plank(depth: Double, handShift: Double = 0, wrists: Bool = true) -> [Joint: PosePoint] {
        let shoulderY = 0.7 - 0.4 * depth
        var image: [Joint: SIMD2<Double>] = [
            .leftShoulder: [0.4, shoulderY], .rightShoulder: [0.6, shoulderY],
            .leftHip: [0.45, shoulderY + 0.12], .rightHip: [0.55, shoulderY + 0.12],
            .leftKnee: [0.45, shoulderY + 0.18], .rightKnee: [0.55, shoulderY + 0.18],
        ]
        if wrists {
            image[.leftWrist] = [0.38 + handShift, 0.7]
            image[.rightWrist] = [0.62 + handShift, 0.7]
        }
        return image.mapValues { PosePoint(position: .zero, image: $0, confidence: 0.9) }
    }

    /// Standing upright; `curl` 1 = arms hanging, 0 = hands at the shoulders.
    func standing(curl: Double) -> [Joint: PosePoint] {
        let image: [Joint: SIMD2<Double>] = [
            .leftShoulder: [0.4, 0.3], .rightShoulder: [0.6, 0.3],
            .leftWrist: [0.4, 0.3 + 0.35 * curl], .rightWrist: [0.6, 0.3 + 0.35 * curl],
            .leftHip: [0.45, 0.55], .rightHip: [0.55, 0.55],
            .leftKnee: [0.45, 0.75], .rightKnee: [0.55, 0.75],
        ]
        return image.mapValues { PosePoint(position: .zero, image: $0, confidence: 0.9) }
    }

    @discardableResult
    mutating func feed(_ d: inout PushupDetector, _ points: [Joint: PosePoint], frames: Int) -> DetectionEvent {
        var last = DetectionEvent.tracking
        for _ in 0..<frames {
            last = d.process(PoseFrame(timestamp: t, processingTime: 0.06, points: points))
            t += Self.dt
        }
        return last
    }

    mutating func getReady(_ d: inout PushupDetector) { feed(&d, plank(depth: 1), frames: 24) }

    mutating func rep(_ d: inout PushupDetector, depth: Double = 0.5, frames: Int = 6) {
        feed(&d, plank(depth: depth), frames: frames)
        feed(&d, plank(depth: 1), frames: frames)
    }

    @Test mutating func countsFullReps() {
        var d = PushupDetector()
        getReady(&d)
        for _ in 0..<3 { rep(&d) }
        #expect(d.count == 3)
    }

    @Test mutating func countsFastReps() {
        var d = PushupDetector()
        getReady(&d)
        // About 0.4 s per rep: two frames down, two up.
        for _ in 0..<5 { rep(&d, frames: 2) }
        #expect(d.count == 5)
    }

    @Test mutating func countsDeepRepsWhereTheBodyDropsOutOfView() {
        var d = PushupDetector()
        getReady(&d)
        for _ in 0..<3 {
            feed(&d, plank(depth: 0.85), frames: 2)
            feed(&d, [:], frames: 5)
            feed(&d, plank(depth: 1), frames: 6)
        }
        #expect(d.count == 3)
    }

    @Test mutating func countsWhenWristsVanishAtTheBottom() {
        var d = PushupDetector()
        getReady(&d)
        feed(&d, plank(depth: 0.5, wrists: false), frames: 6)
        feed(&d, plank(depth: 1), frames: 6)
        #expect(d.count == 1)
    }

    @Test mutating func halfRepsDontCount() {
        var d = PushupDetector()
        getReady(&d)
        for _ in 0..<3 { rep(&d, depth: 0.85) }
        #expect(d.count == 0)
    }

    @Test mutating func leavingTheFrameFromTheTopIsNotARep() {
        var d = PushupDetector()
        getReady(&d)
        feed(&d, [:], frames: 10)
        feed(&d, plank(depth: 1), frames: 6)
        #expect(d.count == 0)
    }

    @Test mutating func nothingCountsBeforeHoldingStill() {
        var d = PushupDetector()
        // Bobbing up and down while getting set up never holds still long enough to arm.
        for _ in 0..<4 { rep(&d, frames: 4) }
        #expect(d.count == 0)
        #expect(feed(&d, plank(depth: 1), frames: 1) == .getReady(.holdStart))
    }

    @Test mutating func standingArmCurlsDontCount() {
        var d = PushupDetector()
        feed(&d, standing(curl: 1), frames: 24)
        for _ in 0..<3 {
            feed(&d, standing(curl: 0.2), frames: 6)
            feed(&d, standing(curl: 1), frames: 6)
        }
        #expect(d.count == 0)
        #expect(feed(&d, standing(curl: 1), frames: 1) == .getReady(.getDown))
    }

    @Test mutating func handsAboveShouldersCantStart() {
        var d = PushupDetector()
        var raised = plank(depth: 1)
        raised[.leftWrist]?.image = [0.38, 0.2]
        raised[.rightWrist]?.image = [0.62, 0.2]
        #expect(feed(&d, raised, frames: 1) == .getReady(.handsOnFloor))
    }

    @Test mutating func movingHandsVoidTheRep() {
        var d = PushupDetector()
        getReady(&d)
        feed(&d, plank(depth: 0.5), frames: 4)
        feed(&d, plank(depth: 0.5, handShift: 0.15), frames: 2)
        feed(&d, plank(depth: 1), frames: 6)
        #expect(d.count == 0)
        rep(&d)
        #expect(d.count == 1)
    }

    @Test mutating func standingUpRequiresGettingReadyAgain() {
        var d = PushupDetector()
        getReady(&d)
        feed(&d, standing(curl: 1), frames: 40)
        rep(&d)
        #expect(d.count == 0)
    }
}

/// Replays real recorded sessions (Settings → Tuning → Record pose data).
@Suite struct RecordedSessionTests {
    struct Recording: Decodable {
        var exercise: Exercise
        var frames: [PoseFrame]
    }

    func load(_ name: String) throws -> Recording {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Recording.self, from: Data(contentsOf: url))
    }

    /// Phone on the floor facing the user, fast and deep reps, ~16 fps. Counted by hand from the
    /// shoulder track and the screen recording: 13 reps, then standing up.
    @Test func frontViewSessionCountsThirteen() throws {
        let recording = try load("pushups-front-13-reps")
        var detector = PushupDetector()
        for frame in recording.frames { _ = detector.process(frame) }
        #expect(detector.count == 13)
    }
}

@Suite struct SquatTests {
    @Test func countsSquats() {
        var d = SquatDetector(), f = PoseFactory()
        func run(_ knee: Double) { for _ in 0..<15 { _ = d.process(f.next(PoseFactory.squat(knee: knee))) } }
        run(175); run(175); run(175)
        run(80); run(175)
        run(60); run(170)
        #expect(d.count == 2)
    }

    @Test func halfSquatDoesNotCount() {
        var d = SquatDetector(), f = PoseFactory()
        func run(_ knee: Double) { for _ in 0..<15 { _ = d.process(f.next(PoseFactory.squat(knee: knee))) } }
        run(175); run(175); run(175)
        run(120); run(175)
        #expect(d.count == 0)
    }
}

@Suite struct PlankTests {
    @Test func countsHeldSeconds() {
        var d = PlankDetector(), f = PoseFactory()
        for _ in 0..<(30 * 3 + 2) { _ = d.process(f.next(PoseFactory.plank())) }
        #expect(d.count == 3)
    }

    @Test func pikedHipsBreakTheHoldButKeepTotal() {
        var d = PlankDetector(), f = PoseFactory()
        for _ in 0..<(30 * 2 + 2) { _ = d.process(f.next(PoseFactory.plank())) }
        #expect(d.count == 2)
        let event = d.process(f.next(PoseFactory.plank(hipLift: 0.6)))
        guard case .badForm(let joints) = event else { Issue.record("expected badForm, got \(event)"); return }
        #expect(joints.contains(.leftHip))
        // A fresh hold of 1.5 s adds exactly one more second.
        for _ in 0..<46 { _ = d.process(f.next(PoseFactory.plank())) }
        #expect(d.count == 3)
    }
}

@Suite struct EarningTests {
    @Test func tableMatchesPushscroll() {
        #expect(EarningRules.minutesPerUnit(.pushups, .medium) == 2)
        #expect(EarningRules.minutesPerUnit(.pushups, .veryEasy) == 10)
        #expect(EarningRules.minutesPerUnit(.squats, .veryHard) == 0.2)
        #expect(EarningRules.minutesPerUnit(.plank, .medium) == 1)
    }

    @Test func fractionalEarningsInSeconds() {
        #expect(EarningRules.earnedSeconds(units: 3, .pushups, .veryHard) == 60)
        #expect(EarningRules.rateLabel(.pushups, .veryHard) == "20 s per rep")
        #expect(EarningRules.rateLabel(.squats, .easy) == "2 min per rep")
    }
}

@Suite struct LedgerTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func sessionDebitsAndRefunds() throws {
        let start = try #require(Ledger.startSession(minutes: 10, bankSeconds: 900, now: now))
        #expect(start.bankSeconds == 300)
        #expect(start.session.expiresAt == now.addingTimeInterval(20 * 60))
        var session = start.session
        session.usedMinutes = 4
        #expect(Ledger.endSession(session, bankSeconds: start.bankSeconds) == 300 + 6 * 60)
    }

    @Test func cannotOverspend() {
        #expect(Ledger.startSession(minutes: 6, bankSeconds: 300, now: now) == nil)
        #expect(Ledger.startSession(minutes: 0, bankSeconds: 300, now: now) == nil)
        #expect(Ledger.spendableMinutes(bankSeconds: 10_000) == 60)
    }

    @Test func shortSessionsGetMinimumInterval() throws {
        let start = try #require(Ledger.startSession(minutes: 1, bankSeconds: 60, now: now))
        #expect(start.session.expiresAt == now.addingTimeInterval(15 * 60))
    }
}

@Suite struct StreakTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400 + 3_600) }

    @Test func currentStreakIncludesToday() {
        #expect(Streaks.current(activeDays: [day(8), day(9), day(10)], today: day(10), calendar: calendar) == 3)
    }

    @Test func streakSurvivesUntilTodayEnds() {
        #expect(Streaks.current(activeDays: [day(8), day(9)], today: day(10), calendar: calendar) == 2)
        #expect(Streaks.current(activeDays: [day(7), day(8)], today: day(10), calendar: calendar) == 0)
    }

    @Test func longestStreak() {
        #expect(Streaks.longest(activeDays: [day(1), day(2), day(5), day(6), day(7)], calendar: calendar) == 3)
    }
}

@Suite struct PlanTests {
    @Test func freePlanAllowsOneRestrictedItem() {
        #expect(Plan.fitsFreePlan(restrictedCount: 0))
        #expect(Plan.fitsFreePlan(restrictedCount: 1))
        #expect(!Plan.fitsFreePlan(restrictedCount: 2))
    }
}
