import Testing
@testable import RowboatCore

@Suite struct LabelAllocatorTests {
    func prefixFree(_ labels: [String]) -> Bool {
        let set = Set(labels)
        for a in labels { for len in 1..<a.count where set.contains(String(a.prefix(len))) { return false } }
        return true
    }

    @Test func labelsAreTwoLettersFirstLetterVaryingFastest() {
        var a = LabelAllocator(alphabet: "asdfjkl")
        #expect(a.next(4) == ["aa", "sa", "da", "fa"])
    }

    @Test func noLabelIsAPrefixOfAnotherAcrossBatches() {
        var a = LabelAllocator(alphabet: "asdfjklghqwertyuiopzxcvbnm")
        let all = a.next(27) + a.next(80) + a.next(400) + a.next(300)
        #expect(Set(all).count == all.count)
        #expect(prefixFree(all))
        #expect(all.allSatisfy { $0.count == 2 || $0.count == 3 })
    }

    @Test func overflowUsesReservedLetterOnly() {
        var a = LabelAllocator(alphabet: "abc")
        let labels = a.next(a.capacity + 5)
        #expect(labels.count == a.capacity)       // stops cleanly at capacity
        #expect(labels.filter { $0.count == 3 }.allSatisfy { $0.hasPrefix("c") })
        #expect(labels.filter { $0.count == 2 }.allSatisfy { !$0.hasPrefix("c") })
        #expect(prefixFree(labels))
    }

    @Test func earlierLabelsNeverChange() {
        var a = LabelAllocator(alphabet: "asdf")
        let first = a.next(3)
        _ = a.next(5)
        #expect(Array(a.assigned.prefix(3)) == first)
    }

    @Test func tinyAlphabetYieldsNothing() {
        var a = LabelAllocator(alphabet: "a")
        #expect(a.next(3) == [])
    }
}
