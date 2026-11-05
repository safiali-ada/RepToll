import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    #if DEBUG
    @State private var tab = DemoMode.screen == .stats ? "stats" : "home"
    #else
    @State private var tab = "home"
    #endif

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasOnboarded {
                TabView(selection: $tab) {
                    Tab("Home", systemImage: "bolt.fill", value: "home") { HomeView() }
                    Tab("Stats", systemImage: "chart.bar.fill", value: "stats") { StatsView() }
                    Tab("Settings", systemImage: "gearshape.fill", value: "settings") { SettingsView() }
                }
            } else {
                OnboardingView()
            }
        }
        .background(Theme.background)
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .unlock: UnlockSheet()
            case .chooseExercise: ExercisePickerView()
            case .paywall(let reason): PaywallView(reason: reason)
            }
        }
        .fullScreenCover(item: $model.activeExercise) { exercise in
            ExerciseSessionView(exercise: exercise, difficulty: model.difficulty, isMuted: model.isMuted,
                                recordsPoses: model.recordsPoses)
        }
        .alert("Couldn't do that", isPresented: .init(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
