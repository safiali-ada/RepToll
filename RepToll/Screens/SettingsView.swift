import FamilyControls
import SwiftUI
import RepTollKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var permissions = Permissions()
    @State private var showPicker = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var recordings: [URL] = []
    @State private var showManageSubscription = false
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

                Section("RepToll Pro") {
                    if store.isPro {
                        LabeledContent("Status", value: "Active")
                        if let renewal = store.renewalDate {
                            LabeledContent("Renews", value: renewal.formatted(date: .abbreviated, time: .omitted))
                        }
                        Button("Manage subscription") { showManageSubscription = true }
                    } else {
                        Button("Unlock RepToll Pro") { model.sheet = .paywall(reason: nil) }
                            .fontWeight(.semibold)
                    }
                    Button("Restore purchases") { Task { await store.restore() } }
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
        }
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
