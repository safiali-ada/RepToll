import ManagedSettings
import ManagedSettingsUI
import UIKit
import UnscrollShared

/// The screen shown in place of a restricted app.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(appName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(appName: webDomain.domain)
    }

    private func makeConfiguration(appName: String?) -> ShieldConfiguration {
        let minutes = SharedStore.shared.bankSeconds / 60
        let name = appName ?? "This app"
        let subtitle = minutes > 0
            ? "\(name) is locked. You have \(minutes) min banked — spend some, or earn more."
            : "\(name) is locked. Do a few reps to earn your scroll."
        let lime = UIColor(red: 0.78, green: 1.0, blue: 0.24, alpha: 1)

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: .black,
            icon: UIImage(systemName: "arrow.uturn.backward.circle.fill")?
                .withTintColor(lime, renderingMode: .alwaysOriginal),
            title: .init(text: "Not so fast.", color: .white),
            subtitle: .init(text: subtitle, color: UIColor.white.withAlphaComponent(0.7)),
            primaryButtonLabel: .init(text: minutes > 0 ? "Use my time" : "Earn time", color: .black),
            primaryButtonBackgroundColor: lime,
            secondaryButtonLabel: .init(text: "Close app", color: .white)
        )
    }
}
