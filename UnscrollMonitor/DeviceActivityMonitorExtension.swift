import DeviceActivity
import Foundation
import UnscrollShared

/// Runs when Screen Time reports usage thresholds or a monitored interval ending, even if the app is closed.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard activity == .budgetSession else { return }
        BudgetController.recordUsage(eventName: event)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        switch activity {
        case .budgetSession:
            BudgetController.handleSessionIntervalEnd()
        case .pauseTimer:
            BudgetController.handlePauseIntervalEnd()
        default:
            break
        }
    }
}
