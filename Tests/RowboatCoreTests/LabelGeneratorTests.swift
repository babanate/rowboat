import Testing
@testable import RowboatCore

@Suite struct LabelGeneratorTests {
    @Test func emptyAlphabetProducesNoLabels() {
        #expect(LabelGenerator(alphabet: "").labels(count: 5) == [])
    }

    @Test func zeroCountProducesNoLabels() {
        #expect(LabelGenerator(alphabet: "asdf").labels(count: 0) == [])
    }

    @Test func singleCharacterLabelsWhenAlphabetIsLargeEnough() {
        #expect(LabelGenerator(alphabet: "asdf").labels(count: 3) == ["a", "s", "d"])
    }

    @Test(arguments: [1, 4, 5, 13, 14, 20, 100, 1000])
    func producesExactlyCountUniqueLabels(n: Int) {
        let labels = LabelGenerator(alphabet: "sadfjklewcmpgh").labels(count: n)
        #expect(labels.count == n)
        #expect(Set(labels).count == n)
    }

    @Test func labelsArePrefixFree() {
        let labels = LabelGenerator(alphabet: "sadfjklewcmpgh").labels(count: 20)
        for a in labels {
            for b in labels where a != b {
                #expect(!b.hasPrefix(a), "\(a) is a prefix of \(b)")
            }
        }
    }

    @Test func mixesLengthsToKeepLabelsShort() {
        // 14 letters, 20 targets: 13 one-letter labels + 7 two-letter labels.
        let labels = LabelGenerator(alphabet: "sadfjklewcmpgh").labels(count: 20)
        #expect(labels.filter { $0.count == 1 }.count == 13)
        #expect(labels.filter { $0.count == 2 }.count == 7)
    }

    @Test func shorterLabelsComeFirst() {
        let lengths = LabelGenerator(alphabet: "asdf").labels(count: 10).map(\.count)
        #expect(lengths == lengths.sorted())
    }

    @Test func duplicateAndUppercaseAlphabetCharactersAreNormalised() {
        #expect(LabelGenerator(alphabet: "AaSs").alphabet == ["a", "s"])
    }

    @Test func singleCharacterAlphabetStillTerminates() {
        let labels = LabelGenerator(alphabet: "a").labels(count: 3)
        #expect(labels.count == 3)
        #expect(Set(labels).count == 3)
    }
}
