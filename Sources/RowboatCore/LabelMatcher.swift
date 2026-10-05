import Foundation

public enum LabelMatch: Equatable, Sendable {
    case none
    case exact(String)
    case partial(remaining: [String])
}

public enum LabelMatcher {
    /// Matches typed characters against labels. Labels are assumed lowercase
    /// and prefix-free, so an exact match is unambiguous.
    public static func match(typed: String, labels: [String]) -> LabelMatch {
        let typed = typed.lowercased()
        if typed.isEmpty { return .partial(remaining: labels) }
        if labels.contains(typed) { return .exact(typed) }
        let remaining = labels.filter { $0.hasPrefix(typed) }
        return remaining.isEmpty ? .none : .partial(remaining: remaining)
    }
}
