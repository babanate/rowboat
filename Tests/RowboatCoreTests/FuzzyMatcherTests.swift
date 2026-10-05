import Testing
@testable import RowboatCore

@Suite struct FuzzyMatcherTests {
    @Test func emptyQueryMatchesNothing() {
        #expect(FuzzyMatcher.score(query: "", in: "Download") == nil)
    }

    @Test func noSubsequenceReturnsNil() {
        #expect(FuzzyMatcher.score(query: "xyz", in: "Download") == nil)
    }

    @Test func prefixScoresHigherThanScatteredSubsequence() throws {
        let prefix = try #require(FuzzyMatcher.score(query: "dow", in: "Download"))
        let scattered = try #require(FuzzyMatcher.score(query: "dow", in: "Decide on window"))
        #expect(prefix > scattered)
    }

    @Test func wordStartScoresHigherThanMidWord() throws {
        let wordStart = try #require(FuzzyMatcher.score(query: "nt", in: "New Tab"))
        let midWord = try #require(FuzzyMatcher.score(query: "nt", in: "Pointer"))
        #expect(wordStart > midWord)
    }

    @Test func caseInsensitive() {
        #expect(FuzzyMatcher.score(query: "DOWN", in: "download") != nil)
    }

    @Test func bestFieldScoreIsUsed() {
        let best = FuzzyMatcher.bestScore(query: "back", fields: ["", "Go Back", "button"])
        #expect(best == FuzzyMatcher.score(query: "back", in: "Go Back"))
    }
}
