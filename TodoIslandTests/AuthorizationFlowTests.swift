import XCTest

@testable import TodoIsland

final class AuthorizationFlowTests: XCTestCase {
  @MainActor
  func testNotDeterminedAccessStartsPinnedAndClearsObsoleteOnboardingPreferences() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defaults.set("obsolete-display", forKey: "selected-display-id")
    defaults.set(true, forKey: "completed-onboarding")
    defer { defaults.removePersistentDomain(forName: #function) }

    let model = AppModel(
      store: AuthorizationFlowReminderStore(authorization: .notDetermined),
      defaults: defaults
    )

    XCTAssertEqual(model.islandState, .pinned)
    XCTAssertNil(defaults.object(forKey: "selected-display-id"))
    XCTAssertNil(defaults.object(forKey: "completed-onboarding"))
  }

  @MainActor
  func testSuccessfulAuthorizationKeepsIslandPinnedAndLoadsFirstList() async {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defer { defaults.removePersistentDomain(forName: #function) }

    let store = AuthorizationFlowReminderStore(
      authorization: .notDetermined,
      requestedAuthorization: .fullAccess
    )
    let model = AppModel(store: store, defaults: defaults)

    await model.requestAccess()

    XCTAssertEqual(model.authorization, .fullAccess)
    XCTAssertEqual(model.islandState, .pinned)
    XCTAssertEqual(model.activeListID, "authorization-list")
    XCTAssertFalse(model.isRequestingAccess)
  }

  @MainActor
  func testRevokingAccessPreservesPinnedDraftAndPreventsSaving() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defer { defaults.removePersistentDomain(forName: #function) }

    let store = AuthorizationFlowReminderStore(authorization: .fullAccess)
    let model = AppModel(store: store, defaults: defaults)
    await model.start()
    let reminder = try XCTUnwrap(model.reminders.first)
    model.pinIsland()
    model.beginEditing(reminder)
    model.draft?.title = "Unsaved title"

    store.authorization = .denied
    model.markApplicationActive()
    model.saveEditing()
    model.collapseIsland()

    XCTAssertEqual(model.authorization, .denied)
    XCTAssertEqual(model.islandState, .collapsed)
    XCTAssertEqual(model.activeListID, "authorization-list")
    XCTAssertEqual(model.editingReminderID, reminder.id)
    XCTAssertEqual(model.draft?.title, "Unsaved title")
    XCTAssertFalse(model.isEditingDraftValidated)
    XCTAssertEqual(store.updatedReminderIDs, [])

    store.authorization = .fullAccess
    model.markApplicationActive()
    XCTAssertFalse(model.canSaveEditingDraft)
    try await Task.sleep(for: .milliseconds(100))

    XCTAssertEqual(model.draft?.title, "Unsaved title")
    XCTAssertTrue(model.canSaveEditingDraft)
  }
}

@MainActor
private final class AuthorizationFlowReminderStore: ReminderStore {
  var onStoreChanged: (() -> Void)?
  var authorization: ReminderAuthorization
  private let requestedAuthorization: ReminderAuthorization
  private(set) var updatedReminderIDs: [String] = []

  init(
    authorization: ReminderAuthorization,
    requestedAuthorization: ReminderAuthorization? = nil
  ) {
    self.authorization = authorization
    self.requestedAuthorization = requestedAuthorization ?? authorization
  }

  func authorizationStatus() -> ReminderAuthorization { authorization }

  func requestFullAccess() async throws -> Bool {
    authorization = requestedAuthorization
    return authorization == .fullAccess
  }

  func fetchLists() async throws -> [ReminderListSnapshot] {
    [ReminderListSnapshot(id: "authorization-list", title: "Authorization", accent: .fallback)]
  }

  func fetchPendingReminders(in listID: String) async throws -> [ReminderSnapshot] {
    [
      ReminderSnapshot(
        id: "authorization-reminder",
        listID: listID,
        title: "Reminder",
        dueDateComponents: nil,
        priority: .none,
        isRecurring: false
      )
    ]
  }

  func createReminder(title: String, in listID: String) async throws {}

  func updateReminder(id: String, from draft: ReminderDraft) async throws {
    updatedReminderIDs.append(id)
  }

  func setCompleted(_ completed: Bool, reminderID: String) async throws {}
  func deleteReminder(id: String) async throws {}
}
