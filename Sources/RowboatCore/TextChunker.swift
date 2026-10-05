import CoreGraphics

/// A recognised word with its frame (top-left origin, screen points).
public struct WordBox: Equatable, Sendable {
    public var text: String
    public var frame: CGRect
    public init(text: String, frame: CGRect) { self.text = text; self.frame = frame }
}

/// Groups words on a line into phrases: a gap wider than `gapFactor` times
/// the line's average character width starts a new phrase. Terminal output
/// and tables put several clickable things on one line; prose stays whole.
public enum TextChunker {
    public static func phrases(from words: [WordBox], gapFactor: CGFloat = 2.5) -> [WordBox] {
        guard !words.isEmpty else { return [] }
        let sorted = words.sorted { $0.frame.minX < $1.frame.minX }
        let totalChars = sorted.reduce(0) { $0 + max(1, $1.text.count) }
        let totalWidth = sorted.reduce(CGFloat(0)) { $0 + $1.frame.width }
        let charWidth = max(1, totalWidth / CGFloat(totalChars))
        var result: [WordBox] = []
        var current = sorted[0]
        for word in sorted.dropFirst() {
            let gap = word.frame.minX - current.frame.maxX
            if gap > gapFactor * charWidth {
                result.append(current)
                current = word
            } else {
                current = WordBox(text: current.text + " " + word.text, frame: current.frame.union(word.frame))
            }
        }
        result.append(current)
        return result
    }

    /// True for text worth a label of its own even inside a phrase: URLs and paths.
    public static func looksLikeLink(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.hasPrefix("http://") || t.hasPrefix("https://") || t.hasPrefix("www.") || t.hasPrefix("/") || t.hasPrefix("~/")
    }
}
