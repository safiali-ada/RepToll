import Foundation

/// What the free plan allows. RepToll Pro (subscription) removes the limit.
public enum Plan {
    /// Free users can restrict one app, category or website.
    public static let freeRestrictedLimit = 1

    public static func fitsFreePlan(restrictedCount: Int) -> Bool {
        restrictedCount <= freeRestrictedLimit
    }
}
