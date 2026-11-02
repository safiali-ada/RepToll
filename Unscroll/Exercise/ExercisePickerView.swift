import SwiftUI
import UnscrollKit

struct ExercisePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Earn time")
                    .font(.largeTitle.bold())
                Text("Pick a move. Your camera counts the reps on-device.")
                    .foregroundStyle(Theme.secondaryText)
            }

            ForEach(Exercise.allCases) { exercise in
                Button {
                    model.activeExercise = exercise
                    dismiss()
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: exercise.symbolName)
                            .font(.title)
                            .frame(width: 56, height: 56)
                            .background(Theme.accent.opacity(0.15), in: .rect(cornerRadius: 16))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.title).font(.title3.bold())
                            Text(EarningRules.rateLabel(exercise, model.difficulty))
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                    }
                    .padding(16)
                    .background(Theme.card, in: .rect(cornerRadius: 22))
                }
                .buttonStyle(.plain)
            }

            Text("Difficulty: \(model.difficulty.title). Change it in Settings.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(24)
        .padding(.top, 12)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
    }
}
