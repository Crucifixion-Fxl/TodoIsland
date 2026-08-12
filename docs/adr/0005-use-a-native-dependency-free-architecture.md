# Use a native dependency-free architecture

Todo Island will use AppKit for window, menu-bar, and focus behavior; SwiftUI for the Island and settings views; EventKit for Reminders; and ServiceManagement for launch at login. The application will target macOS 14 or newer and carry no third-party runtime dependencies, reducing distribution and maintenance risk for a small personal utility.
