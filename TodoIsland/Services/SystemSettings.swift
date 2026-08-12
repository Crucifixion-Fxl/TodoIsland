import AppKit

enum SystemSettings {
  @MainActor
  static func openRemindersPrivacy() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
