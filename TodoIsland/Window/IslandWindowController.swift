import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class IslandWindowController: NSObject, NSWindowDelegate {
  private let model: AppModel
  private let panel = IslandPanel()
  private(set) var appliedState: IslandPresentationState?
  private(set) var appliedHostDisplayID: String?
  private(set) var isCollapsedSurfaceVisible = true
  private(set) var isActivationZoneActive = false
  private var cancellables: Set<AnyCancellable> = []
  private var screenObserver: NSObjectProtocol?
  private var applicationDeactivationObserver: NSObjectProtocol?
  private var pointerDisplayTimer: Timer?
  private var fullScreenTimer: Timer?
  private var hostDisplayTracker = HostDisplayTracker()
  private var isChangingHostDisplay = false
  private var hostDisplayTransitionGeneration = 0
  private var visibilityTransitionGeneration = 0

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
    let initiallyVisible = model.islandState != .collapsed || model.isCollapsedIslandVisible
    panel.alphaValue = initiallyVisible ? 1 : 0
    panel.ignoresMouseEvents = !initiallyVisible
    isCollapsedSurfaceVisible = initiallyVisible
    isActivationZoneActive = !initiallyVisible

    refreshHostDisplay()

    model.$islandState
      .removeDuplicates()
      .sink { [weak self] state in
        guard let self else { return }
        self.applyState(state: state, displayID: self.model.hostDisplayID, animated: true)
      }
      .store(in: &cancellables)

    model.$isCollapsedIslandVisible
      .removeDuplicates()
      .sink { [weak self] _ in
        self?.updateVisibility(animated: true)
      }
      .store(in: &cancellables)

    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        if !self.refreshHostDisplay(interruptsTransition: true) {
          self.applyState(
            state: self.model.islandState,
            displayID: self.model.hostDisplayID,
            animated: false
          )
        }
      }
    }

    applicationDeactivationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard
          self?.model.islandState == .pinned,
          self?.model.isRequestingAccess == false
        else { return }
        self?.model.collapseIsland()
      }
    }

    pointerDisplayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
      [weak self] _ in
      Task { @MainActor in
        self?.refreshHostDisplay()
        self?.refreshActivationZoneHover()
      }
    }

    fullScreenTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.updateVisibility(animated: false) }
    }
  }

  isolated deinit {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    if let applicationDeactivationObserver {
      NotificationCenter.default.removeObserver(applicationDeactivationObserver)
    }
    pointerDisplayTimer?.invalidate()
    fullScreenTimer?.invalidate()
  }

  func show() {
    refreshHostDisplay()
    applyState(
      state: model.islandState,
      displayID: model.hostDisplayID,
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

  @discardableResult
  private func refreshHostDisplay(
    now: TimeInterval = ProcessInfo.processInfo.systemUptime,
    interruptsTransition: Bool = false
  ) -> Bool {
    guard !isChangingHostDisplay || interruptsTransition else { return false }
    if interruptsTransition {
      isChangingHostDisplay = false
    }

    let pointerDisplayID = DisplaySupport.screenContainingPointer()?.todoIslandDisplayID
    let fallbackDisplayID = DisplaySupport.fallbackScreen()?.todoIslandDisplayID
    guard
      let change = hostDisplayTracker.observe(
        pointerDisplayID: pointerDisplayID,
        fallbackDisplayID: fallbackDisplayID,
        availableDisplayIDs: DisplaySupport.availableDisplayIDs(),
        locksHostDisplay: model.islandState != .collapsed,
        now: now
      )
    else { return false }

    applyHostDisplayChange(change)
    return true
  }

  private func applyHostDisplayChange(_ change: HostDisplayChange) {
    hostDisplayTransitionGeneration += 1
    let transitionGeneration = hostDisplayTransitionGeneration
    appliedHostDisplayID = change.displayID
    model.setHostDisplayID(change.displayID)

    let shouldFade =
      change.reason == .pointerDwell
      && panel.isVisible
      && panel.alphaValue > 0.01
      && shouldShowSurface(state: model.islandState)
      && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    guard shouldFade else {
      isChangingHostDisplay = false
      applyState(state: model.islandState, displayID: change.displayID, animated: false)
      return
    }

    isChangingHostDisplay = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.1
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        guard self.hostDisplayTransitionGeneration == transitionGeneration else {
          self.isChangingHostDisplay = false
          self.updateVisibility(animated: false)
          return
        }
        self.applyState(state: self.model.islandState, displayID: change.displayID, animated: false)
        self.panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.12
          context.timingFunction = CAMediaTimingFunction(name: .easeOut)
          self.panel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
          Task { @MainActor in
            guard self?.hostDisplayTransitionGeneration == transitionGeneration else { return }
            self?.isChangingHostDisplay = false
            self?.updateVisibility(animated: false)
          }
        }
      }
    }
  }

  private func applyState(
    state: IslandPresentationState,
    displayID: String?,
    animated: Bool
  ) {
    let previousState = appliedState
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
        context.allowsImplicitAnimation = true
        context.timingFunction = windowTimingFunction(from: previousState, to: state)
        panel.animator().setFrame(frame, display: true)
      }
    } else {
      panel.setFrame(frame, display: true)
    }

    if state == .pinned {
      NSApp.activate(ignoringOtherApps: true)
      panel.makeKeyAndOrderFront(nil)
    } else {
      if panel.isKeyWindow {
        panel.resignKey()
        NSApp.deactivate()
      }
      panel.orderFrontRegardless()
    }
    updateVisibility(state: state, displayID: displayID, animated: animated)
  }

  private func windowTimingFunction(
    from previousState: IslandPresentationState?,
    to state: IslandPresentationState
  ) -> CAMediaTimingFunction {
    switch (previousState, state) {
    case (.preview, .pinned):
      CAMediaTimingFunction(controlPoints: 0.22, 0.82, 0.20, 1)
    case (_, .collapsed):
      CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
    default:
      CAMediaTimingFunction(controlPoints: 0.20, 0.84, 0.18, 1)
    }
  }

  private func updateVisibility(animated: Bool) {
    updateVisibility(
      state: model.islandState,
      displayID: model.hostDisplayID,
      animated: animated
    )
  }

  private func updateVisibility(
    state: IslandPresentationState,
    displayID: String?,
    animated: Bool
  ) {
    guard let screen = DisplaySupport.screen(id: displayID) else {
      panel.orderOut(nil)
      isCollapsedSurfaceVisible = false
      isActivationZoneActive = false
      return
    }

    if state != .pinned && DisplaySupport.shouldHideFallbackInFullScreen(screen) {
      panel.orderOut(nil)
      isCollapsedSurfaceVisible = false
      isActivationZoneActive = false
      return
    }

    if !panel.isVisible {
      if state == .pinned {
        panel.makeKeyAndOrderFront(nil)
      } else {
        panel.orderFrontRegardless()
      }
    }

    applySurfaceVisibility(
      shouldShowSurface(state: state),
      animated: animated && state == .collapsed
    )
  }

  private func shouldShowSurface(state: IslandPresentationState) -> Bool {
    state != .collapsed
      || model.isCollapsedIslandVisible
      || NSWorkspace.shared.isVoiceOverEnabled
  }

  private func applySurfaceVisibility(_ visible: Bool, animated: Bool) {
    visibilityTransitionGeneration += 1
    let generation = visibilityTransitionGeneration
    isCollapsedSurfaceVisible = visible
    isActivationZoneActive = !visible && model.islandState == .collapsed
    panel.ignoresMouseEvents = !visible

    let targetAlpha: CGFloat = visible ? 1 : 0
    guard abs(panel.alphaValue - targetAlpha) > 0.001 else {
      panel.alphaValue = targetAlpha
      return
    }

    guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      panel.alphaValue = targetAlpha
      return
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(
        name: visible ? .easeOut : .easeIn
      )
      panel.animator().alphaValue = targetAlpha
    } completionHandler: { [weak self] in
      Task { @MainActor in
        guard let self, self.visibilityTransitionGeneration == generation else { return }
        self.panel.alphaValue = targetAlpha
      }
    }
  }

  private func refreshActivationZoneHover() {
    guard
      model.islandState == .collapsed,
      model.usesAutoHiddenCollapsedIsland,
      !NSWorkspace.shared.isVoiceOverEnabled,
      let screen = DisplaySupport.screen(id: model.hostDisplayID),
      !DisplaySupport.shouldHideFallbackInFullScreen(screen),
      panel.isVisible
    else { return }

    model.setIslandHovered(panel.frame.contains(NSEvent.mouseLocation))
  }
}
