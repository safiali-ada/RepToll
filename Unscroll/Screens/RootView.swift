import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.hasOnboarded {
                TabView {
                    Tab("Home", systemImage: "bolt.fill") { HomeView() }
                    Tab("Stats", systemImage: "chart.bar.fill") { StatsView() }
                    Tab("Settings", systemImage: "gearshape.fill") { SettingsView() }
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
            }
        }
        .fullScreenCover(item: $model.activeExercise) { exercise in
            ExerciseSessionView(exercise: exercise, difficulty: model.difficulty, isMuted: model.isMuted)
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
