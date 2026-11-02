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

@Suite struct PushupTests {
    /// Front view from a phone on the floor, in push-up position.
    static let plankImage: [Joint: SIMD2<Double>] = [
        .leftShoulder: [0.4, 0.3], .rightShoulder: [0.6, 0.3],
        .leftElbow: [0.38, 0.45], .rightElbow: [0.62, 0.45],
        .leftWrist: [0.38, 0.6], .rightWrist: [0.62, 0.6],
        .leftHip: [0.45, 0.42], .rightHip: [0.55, 0.42],
        .leftKnee: [0.45, 0.48], .rightKnee: [0.55, 0.48],
    ]
    /// Standing upright with arms in front of the body.
    static let standingImage: [Joint: SIMD2<Double>] = [
        .leftShoulder: [0.4, 0.3], .rightShoulder: [0.6, 0.3],
        .leftElbow: [0.38, 0.42], .rightElbow: [0.62, 0.42],
        .leftWrist: [0.4, 0.5], .rightWrist: [0.6, 0.5],
        .leftHip: [0.45, 0.55], .rightHip: [0.55, 0.55],
        .leftKnee: [0.45, 0.75], .rightKnee: [0.55, 0.75],
    ]

    func frame(_ f: inout PoseFactory, elbow: Double, right: Double? = nil,
               image: [Joint: SIMD2<Double>] = plankImage, handShift: Double = 0) -> PoseFrame {
        var frame = f.next(PoseFactory.pushup(elbow: elbow, rightElbow: right))
        for (joint, var p) in image {
            if joint == .leftWrist || joint == .rightWrist { p.x += handShift }
            if frame.points[joint] == nil {
                frame.points[joint] = PosePoint(position: .zero, confidence: 0.9)
            }
            frame.points[joint]?.image = p
        }
        return frame
    }

    func run(_ d: inout PushupDetector, _ f: inout PoseFactory, elbow: Double, frames: Int = 15, right: Double? = nil,
             image: [Joint: SIMD2<Double>] = plankImage, handShift: Double = 0) {
        for _ in 0..<frames { _ = d.process(frame(&f, elbow: elbow, right: right, image: image, handShift: handShift)) }
    }

    /// Hold the top position long enough to arm counting.
    func getReady(_ d: inout PushupDetector, _ f: inout PoseFactory) { run(&d, &f, elbow: 170, frames: 45) }

    @Test func countsFullReps() {
        var d = PushupDetector(), f = PoseFactory()
        getReady(&d, &f)
        for _ in 0..<3 {
            run(&d, &f, elbow: 80)
            run(&d, &f, elbow: 170)
        }
        #expect(d.count == 3)
    }

    @Test func nothingCountsBeforeHoldingTheTopPosition() {
        var d = PushupDetector(), f = PoseFactory()
        // Bouncing straight away, like reaching for the phone during setup.
        for _ in 0..<3 {
            run(&d, &f, elbow: 80, frames: 8)
            run(&d, &f, elbow: 170, frames: 8)
        }
        #expect(d.count == 0)
        let event = d.process(frame(&f, elbow: 170))
        #expect(event == .getReady(.holdStart))
    }

    @Test func standingArmBendsDontCount() {
        var d = PushupDetector(), f = PoseFactory()
        run(&d, &f, elbow: 170, frames: 45, image: Self.standingImage)
        for _ in 0..<3 {
            run(&d, &f, elbow: 70, image: Self.standingImage)
            run(&d, &f, elbow: 170, image: Self.standingImage)
        }
        #expect(d.count == 0)
        #expect(d.process(frame(&f, elbow: 170, image: Self.standingImage)) == .getReady(.getDown))
    }

    @Test func handsAboveShouldersAreNotAPushup() {
        var d = PushupDetector(), f = PoseFactory()
        var raised = Self.plankImage
        raised[.leftWrist] = [0.38, 0.25]
        raised[.rightWrist] = [0.62, 0.25]
        #expect(d.process(frame(&f, elbow: 170, image: raised)) == .getReady(.handsOnFloor))
    }

    @Test func movingHandsVoidTheRep() {
        var d = PushupDetector(), f = PoseFactory()
        getReady(&d, &f)
        run(&d, &f, elbow: 80)
        run(&d, &f, elbow: 80, frames: 5, handShift: 0.15)
        run(&d, &f, elbow: 170)
        #expect(d.count == 0)
        // The next clean rep still counts.
        run(&d, &f, elbow: 80)
        run(&d, &f, elbow: 170)
        #expect(d.count == 1)
    }

    @Test func leavingPositionRequiresGettingReadyAgain() {
        var d = PushupDetector(), f = PoseFactory()
        getReady(&d, &f)
        run(&d, &f, elbow: 170, frames: 60, image: Self.standingImage)
        run(&d, &f, elbow: 80)
        run(&d, &f, elbow: 170)
        #expect(d.count == 0)
    }

    @Test func singleNoisyFramesAreIgnored() {
        var d = PushupDetector(), f = PoseFactory()
        getReady(&d, &f)
        for _ in 0..<5 {
            run(&d, &f, elbow: 80, frames: 1)
            run(&d, &f, elbow: 170, frames: 3)
        }
        #expect(d.count == 0)
    }

    @Test func lopsidedArmsDontCount() {
        var d = PushupDetector(), f = PoseFactory()
        getReady(&d, &f)
        run(&d, &f, elbow: 80, right: 160)
        run(&d, &f, elbow: 170)
        #expect(d.count == 0)
    }

    @Test func lowConfidenceReportsNotInFrame() {
        var d = PushupDetector(), f = PoseFactory()
        var weak = frame(&f, elbow: 170)
        for key in weak.points.keys { weak.points[key]?.confidence = 0.1 }
        guard case .notInFrame(let joints) = d.process(weak) else { Issue.record("expected notInFrame"); return }
        #expect(joints.contains(.leftWrist))
    }

    @Test func slowFramesAreSkipped() {
        var d = PushupDetector(), f = PoseFactory()
        func slow(_ elbow: Double, _ n: Int = 15) {
            for _ in 0..<n {
                var fr = frame(&f, elbow: elbow)
                fr.processingTime = 0.2
                _ = d.process(fr)
            }
        }
        slow(170, 45); slow(80); slow(170)
        #expect(d.count == 0)
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
