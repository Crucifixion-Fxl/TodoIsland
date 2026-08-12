import AppKit
import CoreGraphics

struct DisplaySnapshot: Identifiable, Hashable, Sendable {
  let id: String
  let name: String
  let hasPhysicalNotch: Bool
}

@MainActor
enum DisplaySupport {
  static func snapshots() -> [DisplaySnapshot] {
    NSScreen.screens.compactMap { screen in
      guard let id = screen.todoIslandDisplayID else { return nil }
      return DisplaySnapshot(
        id: id,
        name: screen.localizedName,
        hasPhysicalNotch: screen.safeAreaInsets.top > 0
      )
    }
  }

  static func screen(id: String?) -> NSScreen? {
    if let id, let exact = NSScreen.screens.first(where: { $0.todoIslandDisplayID == id }) {
      return exact
    }
    return NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
      ?? NSScreen.screens.first
  }

  static func metrics(for screen: NSScreen) -> DisplayMetrics {
    DisplayMetrics(
      frame: screen.frame,
      visibleFrame: screen.visibleFrame,
      safeAreaTop: screen.safeAreaInsets.top,
      auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
      auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width
    )
  }

  static func shouldHideFallbackInFullScreen(_ screen: NSScreen) -> Bool {
    guard screen.safeAreaInsets.top <= 0 else { return false }
    let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
    guard let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber else {
      return false
    }
    let targetDisplayID = CGDirectDisplayID(screenNumber.uint32Value)
    let regularApplicationPIDs = Set(
      NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && !$0.isTerminated }
        .map(\.processIdentifier))
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[CFString: Any]]
    else { return false }

    return windows.contains { window in
      guard let boundsValue = window[kCGWindowBounds] else { return false }
      let boundsDictionary = boundsValue as! CFDictionary
      guard
        let ownerPID = window[kCGWindowOwnerPID] as? pid_t,
        regularApplicationPIDs.contains(ownerPID),
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
        let displayID = displayContaining(bounds: bounds)
      else { return false }

      return displayID == targetDisplayID
        && abs(bounds.width - screen.frame.width) <= 2
        && abs(bounds.height - screen.frame.height) <= 2
    }
  }

  private static func displayContaining(bounds: CGRect) -> CGDirectDisplayID? {
    var displayID: CGDirectDisplayID = 0
    var count: UInt32 = 0
    let result = CGGetDisplaysWithRect(bounds, 1, &displayID, &count)
    return result == .success && count > 0 ? displayID : nil
  }
}

extension NSScreen {
  var todoIslandDisplayID: String? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let number = deviceDescription[key] as? NSNumber else { return nil }
    let displayID = CGDirectDisplayID(number.uint32Value)
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
    return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
  }
}
