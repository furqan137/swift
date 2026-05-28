import Foundation

// MARK: - Bee Expression Resolver
/// Pure function mapping app state to the appropriate bee expression.
enum BeeExpressionResolver {

    /// Resolves the bee expression based on current app state (priority order).
    static func resolve(
        isScanning: Bool,
        isDeleting: Bool,
        cleanScore: Int,
        pendingGroups: Int,
        daysSinceLastClean: Int?
    ) -> BeeMascot.BeeExpression {
        if isScanning { return .thinking }
        if isDeleting { return .thinking }
        if cleanScore >= 80 { return .proud }
        if cleanScore >= 50 { return .happy }
        if pendingGroups > 20 { return .neutral }
        if let days = daysSinceLastClean, days > 7 { return .sleeping }
        return .waving
    }
}
