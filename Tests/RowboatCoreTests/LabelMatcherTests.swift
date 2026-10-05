import Testing
@testable import RowboatCore

@Suite struct LabelMatcherTests {
    let labels = ["a", "s", "d", "fa", "fs"]

    @Test func emptyInputMatchesEverything() {
        #expect(LabelMatcher.match(typed: "", labels: labels) == .partial(remaining: labels))
    }

    @Test func exactMatch() {
        #expect(LabelMatcher.match(typed: "a", labels: labels) == .exact("a"))
        #expect(LabelMatcher.match(typed: "fs", labels: labels) == .exact("fs"))
    }

    @Test func prefixNarrowsCandidates() {
        #expect(LabelMatcher.match(typed: "f", labels: labels) == .partial(remaining: ["fa", "fs"]))
    }

    @Test func noMatch() {
        #expect(LabelMatcher.match(typed: "z", labels: labels) == .none)
        #expect(LabelMatcher.match(typed: "fz", labels: labels) == .none)
    }

    @Test func matchingIsCaseInsensitive() {
        #expect(LabelMatcher.match(typed: "FA", labels: labels) == .exact("fa"))
    }
}
