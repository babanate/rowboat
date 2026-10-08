import Foundation

/// Hands out fixed-length labels in batches, Homerow-style.
///
/// Every label has two letters, so no label is a prefix of another and the
/// first keystroke never fires a click. The first letter varies fastest
/// (aa, sa, da, ...), so neighbouring targets differ on the first key.
/// The last letter of the alphabet is reserved as a three-letter prefix for
/// overflow (screens with more than (n-1)*n targets). Labels already handed
/// out never change, whatever arrives later.
public struct LabelAllocator {
    public let alphabet: [Character]
    public private(set) var assigned: [String] = []
    private var index = 0

    public init(alphabet: String) {
        alphabet_ = LabelGenerator(alphabet: alphabet).alphabet
        self.alphabet = alphabet_
    }
    private let alphabet_: [Character]

    /// Number of labels available before running out.
    public var capacity: Int {
        let n = alphabet.count
        guard n >= 2 else { return 0 }
        return (n - 1) * n + n * n
    }

    public static func label(at i: Int, alphabet: [Character]) -> String? {
        let n = alphabet.count
        guard n >= 2, i >= 0 else { return nil }
        let twoLetter = (n - 1) * n
        if i < twoLetter {
            return String([alphabet[i % (n - 1)], alphabet[i / (n - 1)]])
        }
        let j = i - twoLetter
        guard j < n * n else { return nil }
        return String([alphabet[n - 1], alphabet[j % n], alphabet[j / n]])
    }

    public mutating func next(_ count: Int) -> [String] {
        var out: [String] = []
        while out.count < count, let label = Self.label(at: index, alphabet: alphabet) {
            out.append(label)
            index += 1
        }
        assigned.append(contentsOf: out)
        return out
    }
}
