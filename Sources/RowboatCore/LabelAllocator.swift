import Foundation

/// Hands out prefix-free labels in batches. Labels already handed out never
/// change; when the pool runs dry the allocator expands a reserved seed
/// label into its children, so later batches (other windows, screen text
/// arriving after the first paint) get longer labels instead of relabelling
/// what the user may already be typing.
public struct LabelAllocator {
    public let alphabet: [Character]
    private var pool: [String]          // unassigned, sorted shortest first; last one is the seed
    public private(set) var assigned: [String] = []

    /// `expected` sizes the initial pool so the first batch gets the shortest labels.
    public init(alphabet: String, expected: Int) {
        let generator = LabelGenerator(alphabet: alphabet)
        self.alphabet = generator.alphabet
        pool = generator.labels(count: max(2, expected + 1))
    }

    public mutating func next(_ count: Int) -> [String] {
        guard count > 0, !alphabet.isEmpty else { return [] }
        var out: [String] = []
        while out.count < count {
            if pool.count <= 1 {
                guard let seed = pool.last else { break }
                pool.removeLast()
                pool.append(contentsOf: alphabet.map { seed + String($0) })
            }
            out.append(pool.removeFirst())
        }
        assigned.append(contentsOf: out)
        return out
    }
}
