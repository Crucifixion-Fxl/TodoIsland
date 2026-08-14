import XCTest

@testable import TodoIsland

final class LocalSourceAppModelTests: XCTestCase {
  func testSwitchingListCreationSourcePreservesEnteredName() {
    XCTAssertFalse(
      ListCreationDraftPolicy.shouldResetName(
        previousSource: .iCloud,
        newSource: .local
      ))
    XCTAssertFalse(
      ListCreationDraftPolicy.shouldResetName(
        previousSource: .local,
        newSource: .iCloud
      ))
  }

  func testOpeningListCreationFormStartsWithAnEmptyName() {
    XCTAssertTrue(
      ListCreationDraftPolicy.shouldResetName(
        previousSource: nil,
        newSource: .iCloud
      ))
  }

  @MainActor
  func testDeniedICloudAuthorizationStillLoadsAndMutatesLocalSource() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defer { defaults.removePersistentDomain(forName: #function) }

    let store = LocalOnlyTestReminderStore()
    let model = AppModel(store: store, defaults: defaults)
    await model.start()

    XCTAssertEqual(model.authorization, .denied)
    XCTAssertEqual(model.activeList?.source, .local)
    XCTAssertTrue(model.canUseActiveList)

    model.quickAddTitle = "Local task"
    model.createQuickReminder()
    try await Task.sleep(for: .milliseconds(50))

    XCTAssertEqual(model.reminders.map(\.title), ["Local task"])
    XCTAssertEqual(store.createdReminderTitles, ["Local task"])
  }

  @MainActor
  func testDeniedICloudAuthorizationOffersRecoveryWhileLocalListIsActive() async {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defer { defaults.removePersistentDomain(forName: #function) }

    let model = AppModel(store: LocalOnlyTestReminderStore(), defaults: defaults)
    await model.start()

    XCTAssertEqual(model.activeList?.source, .local)
    XCTAssertEqual(model.iCloudSourceMenuState, .authorizationRequired)
  }

  @MainActor
  func testDefaultLocalListIsCreatedOnlyOnFirstUse() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defaults.set(
      CollapsedIslandVisibility.alwaysVisible.rawValue,
      forKey: "collapsed-island-visibility"
    )
    defer { defaults.removePersistentDomain(forName: #function) }

    let store = LocalOnlyTestReminderStore(startsEmpty: true)
    let model = AppModel(store: store, defaults: defaults)
    await model.start()

    await model.useLocal()
    XCTAssertEqual(store.createdListTitles, ["Todo Island"])
    XCTAssertEqual(model.activeList?.source, .local)

    store.removeAllLists()
    await model.reload()
    await model.useLocal()

    XCTAssertEqual(store.createdListTitles, ["Todo Island"])
    XCTAssertEqual(model.requestedListCreationSource, .local)
  }

  @MainActor
  func testDeletingLastLocalListShowsLocalEmptyStateWithoutRecreatingDefault() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defaults.set(
      CollapsedIslandVisibility.alwaysVisible.rawValue,
      forKey: "collapsed-island-visibility"
    )
    defer { defaults.removePersistentDomain(forName: #function) }

    let store = LocalOnlyTestReminderStore()
    let model = AppModel(store: store, defaults: defaults)
    await model.start()
    let list = try XCTUnwrap(model.activeList)

    await model.prepareListDeletion(list)
    let candidate = try XCTUnwrap(model.listDeletionCandidate)
    await model.confirmListDeletion(candidate)

    XCTAssertNil(model.activeList)
    XCTAssertEqual(model.preferredEmptySource, .local)
    XCTAssertEqual(store.createdListTitles, [])

    await model.useLocal()
    XCTAssertEqual(store.createdListTitles, [])
    XCTAssertEqual(model.requestedListCreationSource, .local)
  }

  @MainActor
  func testConfirmationDialogDismissalDoesNotCancelListDeletion() async throws {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    defer { defaults.removePersistentDomain(forName: #function) }

    let store = LocalOnlyTestReminderStore()
    let model = AppModel(store: store, defaults: defaults)
    await model.start()
    let list = try XCTUnwrap(model.activeList)

    await model.prepareListDeletion(list)
    let candidate = try XCTUnwrap(model.listDeletionCandidate)
    model.cancelListDeletion()
    await model.confirmListDeletion(candidate)

    let remainingLists = try await store.fetchLists()
    XCTAssertFalse(remainingLists.contains(where: { $0.id == list.id }))
  }
}

@MainActor
private final class LocalOnlyTestReminderStore: ReminderStore {
  var onStoreChanged: (() -> Void)?
  private var lists: [ReminderListSnapshot]
  private var reminders: [ReminderSnapshot] = []
  private(set) var createdListTitles: [String] = []
  private(set) var createdReminderTitles: [String] = []

  init(startsEmpty: Bool = false) {
    lists = startsEmpty
      ? []
      : [
        ReminderListSnapshot(
          id: "local:test-list",
          title: "Local",
          accent: .fallback,
          source: .local
        )
      ]
  }

  func authorizationStatus() -> ReminderAuthorization { .denied }
  func requestFullAccess() async throws -> Bool { false }
  func fetchLists() async throws -> [ReminderListSnapshot] { lists }
  func fetchPendingReminders(in listID: String) async throws -> [ReminderSnapshot] {
    reminders.filter { $0.listID == listID }
  }

  func createReminder(title: String, in listID: String) async throws {
    createdReminderTitles.append(title)
    reminders.append(
      ReminderSnapshot(
        id: "local:reminder-\(reminders.count)",
        listID: listID,
        source: .local,
        title: title,
        dueDateComponents: nil,
        priority: .none,
        isRecurring: false
      ))
  }

  func updateReminder(id: String, from draft: ReminderDraft) async throws {}
  func setCompleted(_ completed: Bool, reminderID: String) async throws {}
  func deleteReminder(id: String) async throws {}

  func createList(title: String, source: ReminderSource) async throws -> ReminderListSnapshot {
    createdListTitles.append(title)
    let list = ReminderListSnapshot(
      id: "local:created-\(createdListTitles.count)",
      title: title,
      accent: .fallback,
      source: .local
    )
    lists.append(list)
    return list
  }

  func deletionSummary(forListID id: String) async throws -> ReminderListDeletionSummary {
    guard let list = lists.first(where: { $0.id == id }) else {
      throw ReminderStoreError.listNotFound
    }
    return ReminderListDeletionSummary(
      list: list,
      pendingCount: reminders.filter { $0.listID == id }.count,
      completedCount: 0
    )
  }

  func deleteList(id: String) async throws {
    lists.removeAll { $0.id == id }
    reminders.removeAll { $0.listID == id }
  }

  func removeAllLists() {
    lists = []
    reminders = []
  }
}
