import XCTest

@testable import TodoIsland

final class DisplayGeometryTests: XCTestCase {
  func testAnimatedSurfaceTracksCurrentWindowSize() {
    let intermediateWindowSize = CGSize(width: 372, height: 126)
    let previewTargetSize = CGSize(width: 440, height: 220)

    XCTAssertEqual(
      IslandAnimatedSurfaceLayout.surfaceSize(
        windowSize: intermediateWindowSize,
        targetSize: previewTargetSize
      ),
      intermediateWindowSize
    )
  }

  func testPhysicalNotchUsesSafeAreaHeightAndCentersAtTop() {
    let display = DisplayMetrics(
      frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
      visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
      safeAreaTop: 32,
      auxiliaryLeftWidth: 654,
      auxiliaryRightWidth: 654
    )

    let geometry = DisplayGeometryCalculator.geometry(for: display)
    XCTAssertEqual(geometry.collapsedSize.height, 32)
    XCTAssertEqual(geometry.collapsedSize.width, 320)
    XCTAssertEqual(geometry.expandedSize, CGSize(width: 480, height: 360))
    XCTAssertEqual(geometry.origin(for: .pinned, in: display), CGPoint(x: 516, y: 622))
  }

  func testHoverPreviewIsShorterThanPinnedIsland() {
    let display = DisplayMetrics(
      frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
      visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
      safeAreaTop: 32,
      auxiliaryLeftWidth: 654,
      auxiliaryRightWidth: 654
    )

    let geometry = DisplayGeometryCalculator.geometry(for: display)

    XCTAssertLessThan(
      geometry.size(for: .preview).height,
      geometry.size(for: .pinned).height
    )
  }

  func testNoNotchUsesMenuBarHeightAndCapsuleWidth() {
    let display = DisplayMetrics(
      frame: CGRect(x: 100, y: 50, width: 1440, height: 900),
      visibleFrame: CGRect(x: 100, y: 50, width: 1440, height: 875),
      safeAreaTop: 0,
      auxiliaryLeftWidth: nil,
      auxiliaryRightWidth: nil
    )

    let geometry = DisplayGeometryCalculator.geometry(for: display)
    XCTAssertEqual(geometry.collapsedSize, CGSize(width: 340, height: 25 + 5))
    XCTAssertEqual(geometry.origin(for: .collapsed, in: display), CGPoint(x: 650, y: 920))
  }
}
