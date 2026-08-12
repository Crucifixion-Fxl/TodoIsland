import Foundation

@MainActor
protocol ReminderStore: AnyObject {
  var onStoreChanged: (() -> Void)? { get set }

  func authorizationStatus() -> ReminderAuthorization
  func requestFullAccess() async throws -> Bool
  func fetchLists() async throws -> [ReminderListSnapshot]
  func fetchPendingReminders(in listID: String) async throws -> [ReminderSnapshot]
  func createReminder(title: String, in listID: String) async throws
  func updateReminder(id: String, from draft: ReminderDraft) async throws
  func setCompleted(_ completed: Bool, reminderID: String) async throws
  func deleteReminder(id: String) async throws
}

enum ReminderStoreError: LocalizedError {
  case listNotFound
  case reminderNotFound
  case emptyTitle

  var errorDescription: String? {
    switch self {
    case .listNotFound: String(localized: "error.list-not-found")
    case .reminderNotFound: String(localized: "error.reminder-not-found")
    case .emptyTitle: String(localized: "error.empty-title")
    }
  }
}
