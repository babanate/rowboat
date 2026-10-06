import Testing
@testable import RowboatCore

@Suite struct LabelAllocatorTests {
    func prefixFree(_ labels: [String]) -> Bool {
        for a in labels { for b in labels where a != b { if b.hasPrefix(a) { return false } } }
        return true
    }

    @Test func firstBatchGetsShortLabels() {
        var a = LabelAllocator(alphabet: "asdfjkl", expected: 5)
        let first = a.next(5)
        #expect(first == ["a", "s", "d", "f", "j"])
    }

    @Test func laterBatchesNeverChangeEarlierLabelsAndStayPrefixFree() {
        var a = LabelAllocator(alphabet: "asdfjkl", expected: 5)
        let first = a.next(5)
        let second = a.next(20)
        let third = a.next(60)
        let all = first + second + third
        #expect(Set(all).count == all.count)
        #expect(prefixFree(all))
        #expect(Array(a.assigned.prefix(5)) == first)
    }

    @Test func growsWithoutBound() {
        var a = LabelAllocator(alphabet: "ab", expected: 1)
        let labels = a.next(200)
        #expect(labels.count == 200)
        #expect(prefixFree(labels))
    }

    @Test func emptyAlphabetYieldsNothing() {
        var a = LabelAllocator(alphabet: "", expected: 3)
        #expect(a.next(3) == [])
    }
}
