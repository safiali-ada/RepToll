import SwiftData
import SwiftUI
import RepTollKit

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutRecord.date, order: .reverse) private var records: [WorkoutRecord]
    @State private var permissions = Permissions()

    private var streak: Int { Streaks.current(activeDays: Set(records.map(\.date)), today: .now) }
    private var todayUnits: Int {
        records.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.units }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Wordmark(size: 26)
                    Spacer()
                    if !Store.shared.isPro { goProButton }
                    if !model.isStrict { pauseMenu }
                }
                .padding(.bottom, 4)

                permissionWarnings
                statusBanner
                bankCard

                HStack(spacing: 12) {
                    statTile(value: "\(streak)", label: streak == 1 ? "day streak" : "day streak", symbol: "flame.fill")
                    statTile(value: "\(todayUnits)", label: "reps today", symbol: "figure.strengthtraining.functional")
                }

                Button {
                    model.sheet = .chooseExercise
                } label: {
                    Label("Earn time", systemImage: "bolt.fill")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    model.sheet = .unlock
                } label: {
                    Label("Unlock apps", systemImage: "lock.open.fill")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(model.spendableMinutes == 0 || model.restrictedCount == 0)
                .opacity(model.spendableMinutes == 0 || model.restrictedCount == 0 ? 0.45 : 1)

                if model.restrictedCount == 0 {
                    Text("You haven't restricted any apps yet. Pick some in Settings.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .task(id: scenePhase) { if scenePhase == .active { await permissions.refresh() } }
    }

    private var goProButton: some View {
        Button {
            model.sheet = .paywall(reason: nil)
        } label: {
            Label("Go Pro", systemImage: "sparkles")
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.accent, in: .capsule)
                .foregroundStyle(.black)
        }
    }

    /// Without Screen Time nothing gets locked, and without notifications the shield's button
    /// can't bring the user back here, so say so instead of failing quietly.
    @ViewBuilder
    private var permissionWarnings: some View {
        if permissions.isLoaded && !permissions.screenTime {
            warning("Screen Time is off", "RepToll can't lock any apps until you allow it.") {
                await permissions.requestScreenTime()
            }
        }
        if permissions.isLoaded && !permissions.notifications {
            warning("Notifications are off", "Tapping a locked app can't bring you here to earn time.") {
                await permissions.requestNotifications()
                if !permissions.notifications, let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    await UIApplication.shared.open(url)
                }
            }
        }
    }

    private func warning(_ title: String, _ detail: String, fix: @escaping () async -> Void) -> some View {
        Card {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            Button("Turn on") { Task { await fix() } }
                .font(.subheadline.weight(.semibold))
        }
    }

    private var bankCard: some View {
        Card {
            Text("BANKED SCREEN TIME")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(model.bankMinutes)")
                    .font(Theme.number(72))
                    .foregroundStyle(Theme.accent)
                    .contentTransition(.numericText(value: Double(model.bankMinutes)))
                Text("min")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.secondaryText)
            }
            Text("\(EarningRules.rateLabel(.pushups, model.difficulty)) of push-ups · \(model.difficulty.title)")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .animation(.snappy, value: model.bankMinutes)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let session = model.session {
            Card {
                Label("Apps unlocked", systemImage: "lock.open.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text("Up to \(session.remainingMinutes) of \(session.grantedMinutes) min left. Time only counts while you're in restricted apps.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                Button("Lock now & refund the rest") { model.lockNow() }
                    .font(.subheadline.weight(.semibold))
            }
        } else if model.isPaused {
            Card {
                Label("RepToll is paused", systemImage: "pause.circle.fill")
                    .font(.headline)
                if let until = model.pausedUntil {
                    Text("Apps unlock until \(until.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                Button("Resume") { model.resume() }
                    .font(.subheadline.weight(.semibold))
            }
        } else if model.restrictedCount > 0 {
            Label("Restricting \(model.restrictedCount) app\(model.restrictedCount == 1 ? "" : "s")", systemImage: "shield.lefthalf.filled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var pauseMenu: some View {
        Menu {
            if model.isPaused {
                Button("Resume", systemImage: "play.fill") { model.resume() }
            } else {
                Button("Pause for 1 hour", systemImage: "clock") { model.pause(for: 3600) }
                Button("Pause until tomorrow", systemImage: "moon") {
                    let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
                    model.pause(for: tomorrow.timeIntervalSinceNow + 6 * 3600)
                }
                Button("Pause indefinitely", systemImage: "pause") { model.pause(for: nil) }
            }
        } label: {
            Image(systemName: model.isPaused ? "play.circle.fill" : "pause.circle")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .accessibilityLabel(model.isPaused ? "Resume" : "Pause")
    }

    private func statTile(value: String, label: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
            Text(value).font(Theme.number(30))
            Text(label).font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 20))
    }
}
