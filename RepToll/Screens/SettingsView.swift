import FamilyControls
import SwiftUI
import RepTollKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var permissions = Permissions()
    @State private var showPicker = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var recordings: [URL] = []

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
                    Text("These stay locked until you spend time you've earned.")
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
                if !isShowing { model.saveSelection(draftSelection) }
            }
            .task { await permissions.refresh() }
            .onAppear { recordings = PoseRecorder.recordings() }
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
