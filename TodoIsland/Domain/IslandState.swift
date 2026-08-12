import Foundation

enum IslandPresentationState: Equatable, Sendable {
  case collapsed
  case preview
  case pinned

  var showsQuickAdd: Bool {
    self != .collapsed
  }

  var motionProfile: IslandMotionProfile {
    switch self {
    case .collapsed:
      .closing
    case .preview, .pinned:
      .opening
    }
  }
}

struct IslandMotionProfile: Equatable, Sendable {
  let response: Double
  let dampingFraction: Double

  static let opening = IslandMotionProfile(response: 0.42, dampingFraction: 0.8)
  static let closing = IslandMotionProfile(response: 0.45, dampingFraction: 1.0)
}

struct IslandStateMachine: Equatable, Sendable {
  private(set) var state: IslandPresentationState = .collapsed

  mutating func pointerEntered() {
    if state == .collapsed { state = .preview }
  }

  mutating func pointerExited() {
    if state == .preview { state = .collapsed }
  }

  mutating func click() {
    state = .pinned
  }

  mutating func dismiss() {
    state = .collapsed
  }
}
