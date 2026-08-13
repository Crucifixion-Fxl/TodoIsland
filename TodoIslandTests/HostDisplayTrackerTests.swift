import XCTest

@testable import TodoIsland

final class HostDisplayTrackerTests: XCTestCase {
  func testInitialHostUsesPointerDisplayImmediately() {
    var tracker = HostDisplayTracker()

    let change = tracker.observe(
      pointerDisplayID: "external",
      fallbackDisplayID: "built-in",
      availableDisplayIDs: ["built-in", "external"],
      locksHostDisplay: false,
      now: 0
    )

    XCTAssertEqual(
      change,
      HostDisplayChange(displayID: "external", reason: .initial)
    )
    XCTAssertEqual(tracker.hostDisplayID, "external")
  }

  func testCollapsedHostChangesAfterPointerDwellsForThreeHundredFiftyMilliseconds() {
    var tracker = HostDisplayTracker(hostDisplayID: "built-in")
    let displays: Set<String> = ["built-in", "external"]

    XCTAssertNil(
      tracker.observe(
        pointerDisplayID: "external",
        fallbackDisplayID: "built-in",
        availableDisplayIDs: displays,
        locksHostDisplay: false,
        now: 1
      ))
    XCTAssertNil(
      tracker.observe(
        pointerDisplayID: "external",
        fallbackDisplayID: "built-in",
        availableDisplayIDs: displays,
        locksHostDisplay: false,
        now: 1.34
      ))

    XCTAssertEqual(
      tracker.observe(
        pointerDisplayID: "external",
        fallbackDisplayID: "built-in",
        availableDisplayIDs: displays,
        locksHostDisplay: false,
        now: 1.35
      ),
      HostDisplayChange(displayID: "external", reason: .pointerDwell)
    )
  }

  func testBriefBoundaryCrossingResetsTheDwellCandidate() {
    var tracker = HostDisplayTracker(hostDisplayID: "built-in")
    let displays: Set<String> = ["built-in", "external"]

    XCTAssertNil(
      tracker.observe(
        pointerDisplayID: "external", fallbackDisplayID: "built-in",
        availableDisplayIDs: displays, locksHostDisplay: false, now: 1))
    XCTAssertNil(
      tracker.observe(
        pointerDisplayID: "built-in", fallbackDisplayID: "built-in",
        availableDisplayIDs: displays, locksHostDisplay: false, now: 1.2))
    XCTAssertNil(
      tracker.observe(
        pointerDisplayID: "external", fallbackDisplayID: "built-in",
        availableDisplayIDs: displays, locksHostDisplay: false, now: 1.4))
    XCTAssertNil(
      tracker.observe(
        pointerDisplayID: "external", fallbackDisplayID: "built-in",
        availableDisplayIDs: displays, locksHostDisplay: false, now: 1.7))
    XCTAssertEqual(tracker.hostDisplayID, "built-in")
  }

  func testPreviewAndPinnedStatesLockAnAvailableHostDisplay() {
    var tracker = HostDisplayTracker(hostDisplayID: "built-in")

    let change = tracker.observe(
      pointerDisplayID: "external",
      fallbackDisplayID: "built-in",
      availableDisplayIDs: ["built-in", "external"],
      locksHostDisplay: true,
      now: 10
    )

    XCTAssertNil(change)
    XCTAssertEqual(tracker.hostDisplayID, "built-in")
  }

  func testDisconnectForcesImmediateMigrationEvenWhileLocked() {
    var tracker = HostDisplayTracker(hostDisplayID: "external")

    let change = tracker.observe(
      pointerDisplayID: "built-in",
      fallbackDisplayID: "built-in",
      availableDisplayIDs: ["built-in"],
      locksHostDisplay: true,
      now: 10
    )

    XCTAssertEqual(
      change,
      HostDisplayChange(displayID: "built-in", reason: .disconnected)
    )
    XCTAssertEqual(tracker.hostDisplayID, "built-in")
  }
}
