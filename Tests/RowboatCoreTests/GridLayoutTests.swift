import Testing
import CoreGraphics
@testable import RowboatCore

@Suite struct GridLayoutTests {
    @Test func wideScreenGetsMoreColumnsThanRows() {
        let (c, r) = GridLayout.dimensions(for: CGRect(x: 0, y: 0, width: 1512, height: 982), count: 26)
        #expect(c > r)
        #expect(c * r >= 26)
    }

    @Test func cellsStayInsideAndDontOverlap() {
        let rect = CGRect(x: 100, y: 50, width: 1512, height: 982)
        let cells = GridLayout.cells(in: rect, count: 26)
        #expect(cells.count == 26)
        for c in cells { #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(c)) }
        for i in cells.indices { for j in cells.indices where i < j { #expect(cells[i].intersection(cells[j]).width * cells[i].intersection(cells[j]).height < 0.01) } }
    }

    @Test func emptyInputs() {
        #expect(GridLayout.cells(in: .zero, count: 26).isEmpty)
        #expect(GridLayout.cells(in: CGRect(x: 0, y: 0, width: 10, height: 10), count: 0).isEmpty)
    }
}
