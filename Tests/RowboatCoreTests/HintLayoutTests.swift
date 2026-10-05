import Testing
import CoreGraphics
@testable import RowboatCore

@Suite struct HintLayoutTests {
    @Test func sortsTopToBottomThenLeftToRight() {
        // Screen coordinates: y grows downward (top-left origin).
        let frames = [
            CGRect(x: 100, y: 50, width: 10, height: 10), // row 1, right
            CGRect(x: 0, y: 50, width: 10, height: 10),   // row 1, left
            CGRect(x: 0, y: 10, width: 10, height: 10),   // row 0
        ]
        #expect(HintLayout.readingOrder(frames) == [2, 1, 0])
    }

    @Test func rowBucketingToleratesSmallVerticalJitter() {
        let frames = [
            CGRect(x: 100, y: 52, width: 10, height: 10),
            CGRect(x: 0, y: 50, width: 10, height: 10),
        ]
        #expect(HintLayout.readingOrder(frames, rowTolerance: 8) == [1, 0])
    }

    @Test func dropsDuplicateFrames() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 1, y: 1, width: 98, height: 18),  // nearly identical, nested
            CGRect(x: 200, y: 0, width: 100, height: 20),
        ]
        #expect(HintLayout.dedupe(frames) == [0, 3])
    }

    @Test func separatesOverlappingLabelPositions() {
        let anchors = [CGPoint(x: 10, y: 10), CGPoint(x: 12, y: 11), CGPoint(x: 200, y: 10)]
        let size = CGSize(width: 20, height: 14)
        let placed = HintLayout.placeLabels(anchors: anchors, labelSize: size)
        #expect(placed.count == 3)
        let a = CGRect(origin: placed[0], size: size)
        let b = CGRect(origin: placed[1], size: size)
        #expect(!a.intersects(b), "overlapping labels must be nudged apart")
        #expect(placed[2] == anchors[2], "isolated labels stay on their anchor")
    }
}
