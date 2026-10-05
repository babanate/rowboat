import Foundation

/// Generates prefix-free hint labels from an alphabet.
///
/// Labels are as short as possible: with 14 letters and 20 targets, 13 targets
/// get one letter and 7 get two. Shorter labels come first, and the letters
/// earliest in the alphabet stay single-letter longest, so put the home row
/// first.
public struct LabelGenerator: Sendable {
    public let alphabet: [Character]

    public init(alphabet: String) {
        var seen = Set<Character>()
        var chars: [Character] = []
        for ch in alphabet.lowercased() where !seen.contains(ch) && !ch.isWhitespace {
            seen.insert(ch)
            chars.append(ch)
        }
        self.alphabet = chars
    }

    public func labels(count: Int) -> [String] {
        guard count > 0, !alphabet.isEmpty else { return [] }
        if alphabet.count == 1 {
            let c = alphabet[0]
            return (1...count).map { String(repeating: c, count: $0) }
        }
        var labels = alphabet.map { String($0) }
        // Expand the last label of the shortest length into its children.
        // Appending children keeps the list sorted by length.
        while labels.count < count {
            let minLen = labels[0].count
            let index = labels.lastIndex { $0.count == minLen }!
            let parent = labels.remove(at: index)
            labels.append(contentsOf: alphabet.map { parent + String($0) })
        }
        return Array(labels.prefix(count))
    }
}
