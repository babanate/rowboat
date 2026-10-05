import Testing
import CoreGraphics
@testable import RowboatCore

@Suite struct TextChunkerTests {
    func word(_ t: String, x: CGFloat, w: CGFloat) -> WordBox { WordBox(text: t, frame: CGRect(x: x, y: 0, width: w, height: 10)) }

    @Test func proseStaysOnePhrase() {
        // 8 px per char, single spaces of 8 px
        let words = [word("the", x: 0, w: 24), word("quick", x: 32, w: 40), word("fox", x: 80, w: 24)]
        let p = TextChunker.phrases(from: words)
        #expect(p.count == 1)
        #expect(p[0].text == "the quick fox")
        #expect(p[0].frame == CGRect(x: 0, y: 0, width: 104, height: 10))
    }

    @Test func wideGapsSplitColumns() {
        let words = [word("NAME", x: 0, w: 32), word("SIZE", x: 200, w: 32), word("DATE", x: 400, w: 32)]
        let p = TextChunker.phrases(from: words)
        #expect(p.map(\.text) == ["NAME", "SIZE", "DATE"])
    }

    @Test func unsortedInputIsHandled() {
        let words = [word("b", x: 16, w: 8), word("a", x: 0, w: 8)]
        #expect(TextChunker.phrases(from: words).map(\.text) == ["a b"])
    }

    @Test func linkDetection() {
        #expect(TextChunker.looksLikeLink("https://x.com/home"))
        #expect(TextChunker.looksLikeLink("~/code/rowboat"))
        #expect(!TextChunker.looksLikeLink("hello"))
    }
}
