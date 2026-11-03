import SwiftData
import SwiftUI
import RepTollKit

struct ExerciseSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var session: ExerciseSessionModel
    @State private var showSetup = true

    init(exercise: Exercise, difficulty: Difficulty, isMuted: Bool, recordsPoses: Bool) {
        _session = State(initialValue: ExerciseSessionModel(exercise: exercise, difficulty: difficulty,
                                                            isMuted: isMuted, recordsPoses: recordsPoses))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: session.pipeline.session)
                .ignoresSafeArea()
            SkeletonOverlay(session: session)
                .ignoresSafeArea()
                .opacity(showSetup ? 0 : 1)
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 16) {
                topBar
                scoreboard
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 20)

            if showSetup { setupCard }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: session.count)
        .task(id: showSetup) {
            if !showSetup { await session.start() }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            session.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .accessibilityLabel("Cancel workout")
            Spacer()
            Label(session.exercise.title, systemImage: session.exercise.symbolName)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(.ultraThinMaterial, in: .capsule)
        }
        .padding(.top, 8)
    }

    /// Count and earnings sit at the top so the body in the middle stays visible.
    private var scoreboard: some View {
        HStack(alignment: .lastTextBaseline) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(session.count)")
                    .font(Theme.number(84))
                    .contentTransition(.numericText(value: Double(session.count)))
                    .animation(.snappy, value: session.count)
                Text(session.exercise == .plank ? "sec" : "reps")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatEarned(session.earnedSeconds))
                    .font(Theme.number(26))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: session.earnedSeconds)
                Text(EarningRules.rateLabel(session.exercise, session.difficulty))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .shadow(color: .black.opacity(0.4), radius: 8)
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(session.status.message(for: session.exercise))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(.ultraThinMaterial, in: .capsule)
            .transaction { $0.animation = nil }

            Button("Finish & bank time", action: finish)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(session.count == 0)
                .opacity(session.count == 0 ? 0.5 : 1)
        }
        .padding(.bottom, 12)
    }

    private var setupCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)
            Text("Set up your phone")
                .font(.title2.bold())
            Text(session.exercise.setupTip)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
            Text("Counting starts once you hold the start position for a second.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.secondaryText)
            Button("I'm ready") { withAnimation { showSetup = false } }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(24)
        .background(.regularMaterial, in: .rect(cornerRadius: 28))
        .padding(24)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var statusColor: Color {
        switch session.status {
        case .tracking: Theme.accent
        case .getReady, .badForm: .orange
        case .notInFrame, .cameraDenied: Theme.danger
        case .starting: .gray
        }
    }

    private func finish() {
        let earned = session.earnedSeconds
        modelContext.insert(WorkoutRecord(exercise: session.exercise, difficulty: session.difficulty,
                                          units: session.count, earnedSeconds: earned))
        try? modelContext.save()
        model.earn(seconds: earned)
        dismiss()
    }
}

func formatEarned(_ seconds: Int) -> String {
    let minutes = seconds / 60, rest = seconds % 60
    if minutes == 0 { return "+\(rest)s" }
    return rest == 0 ? "+\(minutes) min" : "+\(minutes)m \(rest)s"
}
