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
            CGRect(x: 0, y: 0, width: 99, height: 19),  // nearly identical, nested
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

@Suite struct LabelAnchorTests {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 24, height: 16)

    @Test func labelOverlapsTheElementsLeftEdge() {
        let frame = CGRect(x: 400, y: 100, width: 200, height: 20)
        let a = HintLayout.labelAnchor(for: frame, labelSize: size, within: visible)
        #expect(a.x == 398)
        #expect(a.y == 102)  // vertically centred on the element
    }

    @Test func labelStaysInsideVisibleHorizontally() {
        let frame = CGRect(x: 0, y: 100, width: 200, height: 20)
        let a = HintLayout.labelAnchor(for: frame, labelSize: size, within: visible)
        #expect(a.x == visible.minX)
        let right = CGRect(x: 990, y: 100, width: 50, height: 20)
        #expect(HintLayout.labelAnchor(for: right, labelSize: size, within: visible).x == visible.maxX - size.width)
    }

    @Test func labelStaysInsideVisibleVertically() {
        let frame = CGRect(x: 400, y: -10, width: 200, height: 12)
        let a = HintLayout.labelAnchor(for: frame, labelSize: size, within: visible)
        #expect(a.y == visible.minY)
    }
}


@Suite struct ContainerTests {
    @Test func containerWithTwoInnerTargetsIsDropped() {
        let frames = [
            CGRect(x: 0, y: 0, width: 500, height: 100),   // post row: contains the next two
            CGRect(x: 10, y: 10, width: 40, height: 40),    // avatar
            CGRect(x: 60, y: 10, width: 200, height: 20),   // name link
            CGRect(x: 600, y: 0, width: 100, height: 20),   // unrelated
        ]
        #expect(HintLayout.dropContainers(frames) == [1, 2, 3])
    }

    @Test func wrapperAroundOneChildIsKept() {
        let frames = [
            CGRect(x: 0, y: 0, width: 200, height: 20),     // link
            CGRect(x: 2, y: 2, width: 190, height: 16),     // its text
        ]
        #expect(HintLayout.dropContainers(frames) == [0, 1])
    }

    @Test func identicalFramesAreNotContainersOfEachOther() {
        let frames = [CGRect(x: 0, y: 0, width: 100, height: 20), CGRect(x: 0, y: 0, width: 100, height: 20), CGRect(x: 0, y: 0, width: 100, height: 20)]
        #expect(HintLayout.dropContainers(frames) == [0, 1, 2])
    }
}
