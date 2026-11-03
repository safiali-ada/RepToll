import FamilyControls
import SwiftData
import SwiftUI
import RepTollKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @State private var permissions = Permissions()
    @State private var showPicker = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var recordings: [URL] = []
    @State private var showManageSubscription = false
    @State private var restoreMessage: String?
    @State private var confirmReset = false
    private let store = Store.shared

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Button {
                        draftSelection = model.selection
                        showPicker = true
                    } label: {
                        LabeledContent("Restricted apps", value: "\(model.restrictedCount)")
                    }
                } footer: {
                    Text(store.isPro
                         ? "These stay locked until you spend time you've earned."
                         : "The free plan locks 1 app. RepToll Pro locks as many as you like.")
                }

                Section {
                    if store.isPro {
                        LabeledContent("Plan", value: store.activePlan?.title ?? "Active")
                        if let renewal = store.renewalDate {
                            LabeledContent("Renews", value: renewal.formatted(date: .abbreviated, time: .omitted))
                        }
                        if store.activePlan != .lifetime {
                            Button("Manage subscription") { showManageSubscription = true }
                        }
                    } else {
                        Button("Unlock RepToll Pro") { model.sheet = .paywall(reason: nil) }
                            .fontWeight(.semibold)
                    }
                    Toggle(isOn: strictModeBinding) {
                        Label("Strict Mode", systemImage: store.isPro ? "lock.shield.fill" : "lock.fill")
                    }
                    Button("Restore purchases") { Task { await restore() } }
                } header: {
                    Text("RepToll Pro")
                } footer: {
                    Text("Strict Mode hides the pause button, so the only way into a locked app is time you've earned.")
                }

                Section("Workout") {
                    Picker("Difficulty", selection: $model.difficulty) {
                        ForEach(Difficulty.allCases) { Text($0.title).tag($0) }
                    }
                    ForEach(Exercise.allCases) { exercise in
                        LabeledContent(exercise.title, value: EarningRules.rateLabel(exercise, model.difficulty))
                    }
                    Toggle("Mute rep count voice", isOn: $model.isMuted)
                }

                #if DEBUG
                Section {
                    Toggle("Record pose data", isOn: $model.recordsPoses)
                    if !recordings.isEmpty {
                        ShareLink(items: recordings) {
                            Label("Share \(recordings.count) recording\(recordings.count == 1 ? "" : "s")",
                                  systemImage: "square.and.arrow.up")
                        }
                        Button("Delete recordings", role: .destructive) {
                            PoseRecorder.deleteAll()
                            recordings = []
                        }
                    }
                } header: {
                    Text("Tuning")
                } footer: {
                    Text("Saves joint positions (no video) from each workout so rep counting can be tuned against real movement.")
                }
                #endif

                Section("Permissions") {
                    permissionRow("Screen Time", granted: permissions.screenTime) { await permissions.requestScreenTime() }
                    permissionRow("Camera", granted: permissions.camera) { await permissions.requestCamera() }
                    permissionRow("Notifications", granted: permissions.notifications) { await permissions.requestNotifications() }
                }

                Section {
                    LabeledContent("Lifetime earned", value: "\(model.store.lifetimeEarnedSeconds / 60) min")
                } footer: {
                    Text("Pose detection runs entirely on your iPhone. No video or data leaves the device.")
                }

                Section {
                    Button("Reset all data", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Unlocks your apps and deletes your earned time, workouts and settings. Your RepToll Pro purchase stays.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .familyActivityPicker(isPresented: $showPicker, selection: $draftSelection)
            .onChange(of: showPicker) { _, isShowing in
                if !isShowing { Task { await model.saveSelectionCheckingPro(draftSelection) } }
            }
            .task { await permissions.refresh() }
            .onAppear { recordings = PoseRecorder.recordings() }
            .manageSubscriptionsSheet(isPresented: $showManageSubscription)
            .alert(restoreMessage ?? "", isPresented: .init(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog("Reset all data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive, action: resetAll)
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    /// Free users see the toggle as an upsell: turning it on opens the paywall instead.
    private var strictModeBinding: Binding<Bool> {
        Binding(
            get: { model.isStrict },
            set: { isOn in
                if isOn && !store.isPro {
                    model.sheet = .paywall(reason: "Strict Mode is part of RepToll Pro.")
                } else {
                    model.strictMode = isOn
                }
            }
        )
    }

    private func restore() async {
        restoreMessage = switch await store.restore() {
        case .restored: "RepToll Pro is active again."
        case .nothingFound: "No RepToll Pro purchase found for this Apple Account."
        case .failed: "Couldn't reach the App Store. Try again in a moment."
        }
    }

    private func resetAll() {
        try? modelContext.delete(model: WorkoutRecord.self)
        try? modelContext.save()
        recordings = []
        model.resetAllData()
    }

    private func permissionRow(_ title: String, granted: Bool, request: @escaping () async -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            } else {
                Button("Allow") { Task { await request() } }
            }
        }
    }
}
