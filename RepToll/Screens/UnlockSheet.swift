import SwiftUI
import RepTollKit

/// Spend banked minutes. A short countdown adds friction so unlocking is a choice, not a reflex.
struct UnlockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 5
    @State private var countdown = 5

    private let presets = [1, 5, 10, 15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Unlock apps")
                    .font(.largeTitle.bold())
                Text("You have \(model.bankMinutes) min banked.")
                    .foregroundStyle(Theme.secondaryText)
            }

            if model.spendableMinutes == 0 {
                Text("Nothing to spend yet. Do a quick set first.")
                    .foregroundStyle(Theme.secondaryText)
                Button("Earn time") {
                    model.sheet = .chooseExercise
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(presets.filter { $0 <= model.spendableMinutes }, id: \.self) { value in
                        Button {
                            minutes = value
                        } label: {
                            Text("\(value) min")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(minutes == value ? Theme.accent : Theme.card, in: .rect(cornerRadius: 14))
                                .foregroundStyle(minutes == value ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Stepper("Exactly \(minutes) min", value: $minutes, in: 1...max(1, model.spendableMinutes))
                    .font(.subheadline)

                Text("Time only counts while you're in restricted apps. Whatever you don't use comes back to your bank after a \(Ledger.breakWindowMinutes)-minute break.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)

                Button(countdown > 0 ? "Unlock (wait \(countdown)s)" : "Unlock for \(minutes) min") {
                    if model.unlock(minutes: minutes) { dismiss() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(countdown > 0)
                .opacity(countdown > 0 ? 0.6 : 1)
                .contentTransition(.numericText())
            }

            Button("Never mind") { dismiss() }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(24)
        .padding(.top, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.black)
        .onAppear { minutes = min(minutes, max(1, model.spendableMinutes)) }
        .task {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                withAnimation { countdown -= 1 }
            }
        }
    }
}
