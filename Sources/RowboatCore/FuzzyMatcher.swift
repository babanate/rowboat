import Foundation

/// Subsequence matcher for search mode. Higher is better; nil means no match.
public enum FuzzyMatcher {
    static let wordStartBonus = 3.0
    static let consecutiveBonus = 4.0
    static let plainBonus = 1.0
    static let gapPenalty = 0.5

    public static func score(query: String, in text: String) -> Double? {
        let q = Array(query.lowercased())
        let t = Array(text.lowercased())
        guard !q.isEmpty, !t.isEmpty else { return nil }

        var score = 0.0
        var ti = 0
        var lastMatch = -1
        for qc in q {
            var found = false
            while ti < t.count {
                let tc = t[ti]
                if tc == qc {
                    let gap = ti - lastMatch - 1
                    score -= Double(gap) * gapPenalty
                    if lastMatch == ti - 1 && lastMatch >= 0 {
                        score += consecutiveBonus
                    } else if ti == 0 || !(t[ti - 1].isLetter || t[ti - 1].isNumber) {
                        score += wordStartBonus
                    } else {
                        score += plainBonus
                    }
                    lastMatch = ti
                    ti += 1
                    found = true
                    break
                }
                ti += 1
            }
            if !found { return nil }
        }
        return score
    }

    /// Best score across several text fields (title, description, value...).
    public static func bestScore(query: String, fields: [String]) -> Double? {
        fields.compactMap { score(query: query, in: $0) }.max()
    }
}
