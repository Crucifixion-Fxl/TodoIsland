import AppKit
import SwiftUI

struct KeyboardEventMonitor: NSViewRepresentable {
  let handler: @MainActor (NSEvent) -> Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(handler: handler)
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.start()
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.handler = handler
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.stop()
  }

  @MainActor
  final class Coordinator {
    var handler: @MainActor (NSEvent) -> Bool
    private var monitor: Any?

    init(handler: @escaping @MainActor (NSEvent) -> Bool) {
      self.handler = handler
    }

    func start() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else { return event }
        return self.handler(event) ? nil : event
      }
    }

    func stop() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
    }
  }
}
