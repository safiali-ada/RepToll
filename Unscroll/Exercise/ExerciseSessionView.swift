import SwiftData
import SwiftUI
import UnscrollKit

struct ExerciseSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var session: ExerciseSessionModel
    @State private var showSetup = true

    init(exercise: Exercise, difficulty: Difficulty, isMuted: Bool) {
        _session = State(initialValue: ExerciseSessionModel(exercise: exercise, difficulty: difficulty, isMuted: isMuted))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: session.pipeline.session)
                .ignoresSafeArea()
            SkeletonOverlay(points: session.overlay, imageSize: session.imageSize, problems: session.problems)
                .ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.7), .clear, .clear, .black.opacity(0.85)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                counter
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
        .onDisappear { session.stop() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
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

    private var counter: some View {
        VStack(spacing: 4) {
            Text("\(session.count)")
                .font(Theme.number(140))
                .contentTransition(.numericText(value: Double(session.count)))
                .animation(.snappy, value: session.count)
                .shadow(color: .black.opacity(0.5), radius: 12)
            Text(session.exercise == .plank ? "seconds held" : "reps")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(session.status.message)
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.ultraThinMaterial, in: .capsule)
            .animation(.default, value: session.status)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Earned")
                        .font(.caption).foregroundStyle(Theme.secondaryText)
                    Text(formatEarned(session.earnedSeconds))
                        .font(Theme.number(28))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                }
                Spacer()
                Text(EarningRules.rateLabel(session.exercise, session.difficulty))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
            }

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
        case .badForm: .orange
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
