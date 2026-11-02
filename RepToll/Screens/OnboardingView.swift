import FamilyControls
import SwiftUI
import RepTollKit

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    @State private var permissions = Permissions()
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                howItWorks.tag(1)
                difficulty.tag(2)
                permissionsPage.tag(3)
                pickApps.tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.snappy, value: page)

            HStack(spacing: 6) {
                ForEach(0..<5) { index in
                    Capsule()
                        .fill(index == page ? Theme.accent : .white.opacity(0.2))
                        .frame(width: index == page ? 22 : 8, height: 8)
                }
            }
            .animation(.snappy, value: page)
            .padding(.bottom, 16)
        }
        .background(Theme.background)
        .task { await permissions.refresh() }
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: showPicker) { _, isShowing in
            if !isShowing { Task { await model.saveSelectionCheckingPro(selection) } }
        }
    }

    private func page<Content: View>(@ViewBuilder _ content: () -> Content, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            content()
            Spacer()
            Button(button, action: action)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
    }

    private var welcome: some View {
        page({
            Wordmark(size: 40)
            Text("Earn your scroll.")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
            Text("Your most addictive apps stay locked. Push-ups, squats or a plank unlock them, one rep at a time.")
                .font(.title3)
                .foregroundStyle(Theme.secondaryText)
        }, button: "Let's go") { page = 1 }
    }

    private var howItWorks: some View {
        page({
            Text("How it works").font(.largeTitle.bold())
            step(1, "Pick the apps that eat your day", "They get locked behind a shield.")
            step(2, "Exercise in front of your camera", "Reps are counted on-device and turned into minutes.")
            step(3, "Spend minutes when you need them", "Time only ticks while you're actually scrolling.")
        }, button: "Continue") { page = 2 }
    }

    private var difficulty: some View {
        @Bindable var model = model
        return page({
            Text("How hard should it be?").font(.largeTitle.bold())
            Text("You can change this later.").foregroundStyle(Theme.secondaryText)
            ForEach(Difficulty.allCases) { level in
                Button {
                    model.difficulty = level
                } label: {
                    HStack {
                        Text(level.title).font(.headline)
                        Spacer()
                        Text(EarningRules.rateLabel(.pushups, level)).font(.subheadline)
                    }
                    .padding(16)
                    .foregroundStyle(model.difficulty == level ? .black : .white)
                    .background(model.difficulty == level ? Theme.accent : Theme.card, in: .rect(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }, button: "Continue") { page = 3 }
    }

    private var permissionsPage: some View {
        page({
            Text("Three permissions").font(.largeTitle.bold())
            permissionCard("Screen Time", "To lock and unlock the apps you choose.", "hourglass", permissions.screenTime) {
                await permissions.requestScreenTime()
            }
            permissionCard("Camera", "To count your reps. Video never leaves your phone.", "camera.fill", permissions.camera) {
                await permissions.requestCamera()
            }
            permissionCard("Notifications", "So tapping a locked app brings you here.", "bell.fill", permissions.notifications) {
                await permissions.requestNotifications()
            }
        }, button: permissions.allGranted ? "Continue" : "Skip for now") { page = 4 }
    }

    private var pickApps: some View {
        page({
            Text("What do you doomscroll?").font(.largeTitle.bold())
            Text("Pick the apps and categories RepToll should lock.")
                .foregroundStyle(Theme.secondaryText)
            Button {
                showPicker = true
            } label: {
                Label(model.restrictedCount == 0 ? "Choose apps" : "\(model.restrictedCount) selected — edit",
                      systemImage: "apps.iphone")
            }
            .buttonStyle(SecondaryButtonStyle())
        }, button: "Start earning") { model.finishOnboarding() }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(Theme.number(18))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(Theme.accent, in: .circle)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func permissionCard(_ title: String, _ detail: String, _ symbol: String, _ granted: Bool,
                                request: @escaping () async -> Void) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Theme.accent)
            } else {
                Button("Allow") { Task { await request() } }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: 18))
    }
}
