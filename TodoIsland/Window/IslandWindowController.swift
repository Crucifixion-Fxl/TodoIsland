import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class IslandWindowController: NSObject, NSWindowDelegate {
  private let model: AppModel
  private let panel = IslandPanel()
  private(set) var appliedState: IslandPresentationState?
  private var cancellables: Set<AnyCancellable> = []
  private var screenObserver: NSObjectProtocol?
  private var applicationDeactivationObserver: NSObjectProtocol?
  private var fullScreenTimer: Timer?

  init(model: AppModel) {
    self.model = model
    super.init()

    panel.delegate = self
    let hostingView = NSHostingView(
      rootView: AnyView(IslandRootView().environmentObject(model))
    )
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = hostingView

    model.$islandState
      .removeDuplicates()
      .sink { [weak self] state in
        guard let self else { return }
        self.applyState(state: state, displayID: self.model.selectedDisplayID, animated: true)
      }
      .store(in: &cancellables)

    model.$selectedDisplayID
      .removeDuplicates()
      .sink { [weak self] displayID in
        guard let self else { return }
        self.applyState(state: self.model.islandState, displayID: displayID, animated: false)
      }
      .store(in: &cancellables)

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.model.reloadDisplays()
        guard let self else { return }
        self.applyState(
          state: self.model.islandState,
          displayID: self.model.selectedDisplayID,
          animated: false
        )
      }
    }

    applicationDeactivationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard self?.model.islandState == .pinned else { return }
        self?.model.collapseIsland()
      }
    }

    fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateVisibility() }
    }
  }

  isolated deinit {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    if let applicationDeactivationObserver {
      NotificationCenter.default.removeObserver(applicationDeactivationObserver)
    }
    fullScreenTimer?.invalidate()
  }

  func show() {
    applyState(
      state: model.islandState,
      displayID: model.selectedDisplayID,
      animated: false
    )
  }

  func pinAndShow() {
    model.pinIsland()
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func windowDidResignKey(_ notification: Notification) {
    // SwiftUI menus temporarily take key status from the panel. The pinned Island
    // closes when the application deactivates, not during an in-app menu handoff.
  }

  private func applyState(
    state: IslandPresentationState,
    displayID: String?,
    animated: Bool
  ) {
    appliedState = state
    guard let screen = DisplaySupport.screen(id: displayID) else {
      panel.orderOut(nil)
      return
    }

    let metrics = DisplaySupport.metrics(for: screen)
    let geometry = DisplayGeometryCalculator.geometry(for: metrics)
    let frame = NSRect(
      origin: geometry.origin(for: state, in: metrics), size: geometry.size(for: state))

    panel.acceptsKeyInput = state == .pinned
    if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      let motion = state.motionProfile
      NSAnimationContext.runAnimationGroup { context in
        context.duration = motion.response
        context.timingFunction = windowTimingFunction(for: state)
        panel.animator().setFrame(frame, display: true)
      }
    } else {
      panel.setFrame(frame, display: true)
    }

    if state == .pinned {
      panel.makeKeyAndOrderFront(nil)
    } else {
      if panel.isKeyWindow {
        panel.resignKey()
        NSApp.deactivate()
      }
      panel.orderFrontRegardless()
    }
    updateVisibility(state: state, displayID: displayID)
  }

  private func windowTimingFunction(for state: IslandPresentationState) -> CAMediaTimingFunction {
    switch state {
    case .collapsed:
      CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    case .preview, .pinned:
      CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    }
  }

  private func updateVisibility() {
    updateVisibility(state: model.islandState, displayID: model.selectedDisplayID)
  }

  private func updateVisibility(state: IslandPresentationState, displayID: String?) {
    guard let screen = DisplaySupport.screen(id: displayID) else {
      panel.orderOut(nil)
      return
    }

    if DisplaySupport.shouldHideFallbackInFullScreen(screen) {
      panel.orderOut(nil)
    } else if !panel.isVisible {
      if state == .pinned {
        panel.makeKeyAndOrderFront(nil)
      } else {
        panel.orderFrontRegardless()
      }
    }
  }
}
