import AppKit
import Combine
import Foundation

enum ICloudSourceMenuState: Equatable, Sendable {
  case authorizationRequired
  case empty
  case available
}

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var authorization: ReminderAuthorization
  @Published private(set) var lists: [ReminderListSnapshot] = []
  @Published private(set) var reminders: [ReminderSnapshot] = []
  @Published private(set) var islandState: IslandPresentationState = .collapsed
  @Published private(set) var isLoading = false
  @Published private(set) var isRequestingAccess = false
  @Published private(set) var isEditingDraftValidated = true
  @Published private(set) var completingReminderIDs: Set<String> = []
  @Published private(set) var hostDisplayID: String?
  @Published private(set) var localStoreAvailability: LocalStoreAvailability = .available
  @Published private(set) var listDeletionCandidate: ReminderListDeletionSummary?
  @Published private(set) var preferredEmptySource: ReminderSource?
  @Published var requestedListCreationSource: ReminderSource?
  @Published private(set) var quickAddFocusRequestID = UUID()
  @Published private(set) var editingFocusRequestID = UUID()
  @Published var errorMessage: String?
  @Published var activeListID: String? {
    didSet {
      defaults.set(activeListID, forKey: Keys.activeListID)
    }
  }
  @Published var selectedReminderID: String?
  @Published var editingReminderID: String?
  @Published var draft: ReminderDraft?
  @Published var quickAddTitle = ""

  private let store: ReminderStore
  private let defaults: UserDefaults
  private var refreshTask: Task<Void, Never>?
  private var hoverTask: Task<Void, Never>?
  private var isPointerInsideIsland = false
  private var isQuickAddActive = false
  private var suspendedEditingFocus: SuspendedEditingFocus?

  private enum SuspendedEditingFocus {
    case quickAdd
    case reminderEditor
  }

  private enum Keys {
    static let activeListID = "active-list-id"
    static let didInitializeLocalSource = "did-initialize-local-source"
  }

  init(
    store: ReminderStore = SourceAwareReminderStore(),
    defaults: UserDefaults = .standard
  ) {
    self.store = store
    self.defaults = defaults
    authorization = store.authorizationStatus()
    localStoreAvailability = store.localStoreAvailability
    if authorization == .notDetermined {
      islandState = .pinned
    }
    activeListID = defaults.string(forKey: Keys.activeListID)
    hostDisplayID = nil
    defaults.removeObject(forKey: "selected-display-id")
    defaults.removeObject(forKey: "completed-onboarding")

    store.onStoreChanged = { [weak self] in
      self?.scheduleRefresh()
    }
  }

  var activeList: ReminderListSnapshot? {
    lists.first { $0.id == activeListID }
  }

  var iCloudLists: [ReminderListSnapshot] { lists.filter { $0.source == .iCloud } }
  var localLists: [ReminderListSnapshot] { lists.filter { $0.source == .local } }
  var iCloudSourceMenuState: ICloudSourceMenuState {
    guard authorization == .fullAccess else { return .authorizationRequired }
    return iCloudLists.isEmpty ? .empty : .available
  }
  var shouldShowAuthorizationLockInHeader: Bool {
    authorization != .fullAccess && activeList == nil
  }
  var canUseActiveList: Bool {
    guard let activeList else { return false }
    return canAccess(source: activeList.source)
  }
  var nextReminder: ReminderSnapshot? { reminders.first }
  var remainingCount: Int { reminders.count }
  var canSaveEditingDraft: Bool {
    guard
      isEditingDraftValidated,
      let editingReminderID,
      draft != nil
    else { return false }
    return reminders.contains { $0.id == editingReminderID && canAccess(source: $0.source) }
  }

  func start() async {
    authorization = store.authorizationStatus()
    await reload()
    if authorization == .notDetermined, activeList?.source != .local {
      pinIsland()
    } else if activeList?.source == .local, islandState == .pinned {
      collapseIsland()
    }
  }

  func requestAccess() async {
    guard authorization == .notDetermined, !isRequestingAccess else { return }
    isRequestingAccess = true
    defer { isRequestingAccess = false }

    do {
      _ = try await store.requestFullAccess()
      authorization = store.authorizationStatus()
      await reload()
    } catch {
      present(error)
      authorization = store.authorizationStatus()
    }
  }

  func reload() async {
    authorization = store.authorizationStatus()
    localStoreAvailability = store.localStoreAvailability
    isLoading = true
    defer {
      isLoading = false
      schedulePointerExitCollapseIfNeeded()
    }

    do {
      let fetchedLists = try await store.fetchLists()
      localStoreAvailability = store.localStoreAvailability
      var newLists = fetchedLists.filter { canAccess(source: $0.source) }
      if authorization != .fullAccess {
        let cachedICloudLists = lists.filter { $0.source == .iCloud }
        newLists = cachedICloudLists + newLists.filter { $0.source == .local }
      }
      lists = newLists
      if newLists.contains(where: { $0.source == .local }) {
        defaults.set(true, forKey: Keys.didInitializeLocalSource)
      }

      if !newLists.contains(where: { $0.id == activeListID }) {
        if let activeListID,
          let migrated = newLists.first(where: {
            $0.source == .iCloud
              && ReminderStoreIdentity.split($0.id)?.rawID == activeListID
          })
        {
          self.activeListID = migrated.id
        } else {
          activeListID = newLists.first(where: {
            $0.source == .iCloud && canAccess(source: $0.source)
          })?.id
            ?? newLists.first(where: {
              $0.source == .local && canAccess(source: $0.source)
            })?.id
        }
      }

      guard let activeListID else {
        reminders = []
        selectedReminderID = nil
        isEditingDraftValidated = editingReminderID == nil
        return
      }
      preferredEmptySource = nil

      guard let activeList, canAccess(source: activeList.source) else {
        if editingReminderID != nil {
          isEditingDraftValidated = false
        }
        return
      }

      let fetched = try await store.fetchPendingReminders(in: activeListID)
      reminders = ReminderSorter.sorted(fetched)
      if !reminders.contains(where: { $0.id == selectedReminderID }) {
        selectedReminderID = reminders.first?.id
      }
      if let editingReminderID {
        isEditingDraftValidated = reminders.contains { $0.id == editingReminderID }
      } else {
        isEditingDraftValidated = true
      }
    } catch {
      present(error)
    }
  }

  func selectList(_ id: String) {
    guard let list = lists.first(where: { $0.id == id }), canAccess(source: list.source) else {
      return
    }
    activeListID = id
    preferredEmptySource = nil
    selectedReminderID = nil
    cancelEditing()
    Task { await reload() }
  }

  func createQuickReminder() {
    let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canUseActiveList, !title.isEmpty, let activeListID else { return }
    quickAddTitle = ""

    Task {
      do {
        try await store.createReminder(title: title, in: activeListID)
        await reload()
      } catch {
        quickAddTitle = title
        present(error)
      }
    }
  }

  func beginEditing(_ reminder: ReminderSnapshot) {
    guard canAccess(source: reminder.source) else { return }
    selectedReminderID = reminder.id
    editingReminderID = reminder.id
    draft = ReminderDraft(reminder: reminder)
    isEditingDraftValidated = true
  }

  func cancelEditing() {
    editingReminderID = nil
    draft = nil
    isEditingDraftValidated = true
  }

  func saveEditing() {
    guard let id = editingReminderID, let draft else { return }
    guard isEditingDraftValidated else { return }
    guard let reminder = reminders.first(where: { $0.id == id }) else {
      errorMessage = ReminderStoreError.reminderNotFound.localizedDescription
      return
    }
    guard canAccess(source: reminder.source) else { return }
    guard !draft.normalizedTitle.isEmpty else {
      errorMessage = ReminderStoreError.emptyTitle.localizedDescription
      return
    }

    Task {
      do {
        try await store.updateReminder(id: id, from: draft)
        if editingReminderID == id, self.draft == draft {
          cancelEditing()
        }
        await reload()
      } catch {
        present(error)
      }
    }
  }

  func complete(_ reminder: ReminderSnapshot) {
    guard
      canAccess(source: reminder.source),
      reminders.contains(where: { $0.id == reminder.id }),
      completingReminderIDs.insert(reminder.id).inserted
    else { return }

    if editingReminderID == reminder.id {
      cancelEditing()
    }

    Task {
      do {
        try await store.setCompleted(true, reminderID: reminder.id)
        try await Task.sleep(for: .milliseconds(200))
        removeCompletedReminder(id: reminder.id)
        await reload()
      } catch {
        completingReminderIDs.remove(reminder.id)
        present(error)
      }
    }
  }

  func delete(_ reminder: ReminderSnapshot) {
    guard canAccess(source: reminder.source) else { return }
    Task {
      do {
        try await store.deleteReminder(id: reminder.id)
        await reload()
      } catch {
        present(error)
      }
    }
  }

  func requestNewList(source: ReminderSource = .iCloud) {
    requestedListCreationSource = source
    pinIsland()
  }

  func cancelListCreation() {
    requestedListCreationSource = nil
  }

  @discardableResult
  func createList(title: String, source: ReminderSource) async -> Bool {
    guard source == .local || authorization == .fullAccess else {
      errorMessage = ReminderStoreError.operationUnsupported.localizedDescription
      return false
    }

    do {
      let list = try await store.createList(title: title, source: source)
      if source == .local {
        defaults.set(true, forKey: Keys.didInitializeLocalSource)
      }
      requestedListCreationSource = nil
      await reload()
      activeListID = lists.contains(where: { $0.id == list.id }) ? list.id : activeListID
      if activeListID == list.id {
        preferredEmptySource = nil
        selectedReminderID = nil
        reminders = []
        quickAddFocusRequestID = UUID()
      }
      return activeListID == list.id
    } catch {
      present(error)
      return false
    }
  }

  @discardableResult
  func renameList(_ list: ReminderListSnapshot, title: String) async -> Bool {
    guard list.source == .local else { return false }
    do {
      try await store.renameList(id: list.id, title: title)
      await reload()
      return true
    } catch {
      present(error)
      return false
    }
  }

  func prepareListDeletion(_ list: ReminderListSnapshot) async {
    guard list.source == .local else { return }
    do {
      listDeletionCandidate = try await store.deletionSummary(forListID: list.id)
    } catch {
      present(error)
    }
  }

  func cancelListDeletion() {
    listDeletionCandidate = nil
  }

  func confirmListDeletion(_ candidate: ReminderListDeletionSummary) async {
    if listDeletionCandidate?.list.id == candidate.list.id {
      listDeletionCandidate = nil
    }
    do {
      try await store.deleteList(id: candidate.list.id)
      if activeListID == candidate.list.id {
        activeListID = nil
        preferredEmptySource = candidate.list.source
      }
      await reload()
    } catch {
      present(error)
    }
  }

  func useLocal() async {
    pinIsland()
    guard localStoreAvailability == .available else {
      errorMessage = ReminderStoreError.localStoreUnavailable.localizedDescription
      return
    }

    if let list = localLists.first {
      defaults.set(true, forKey: Keys.didInitializeLocalSource)
      selectList(list.id)
      return
    }

    if !defaults.bool(forKey: Keys.didInitializeLocalSource) {
      _ = await createList(title: "Todo Island", source: .local)
    } else {
      requestNewList(source: .local)
    }
  }

  func retryLocalStore() async {
    await store.retryLocalStore()
    localStoreAvailability = store.localStoreAvailability
    await reload()
  }

  func showLocalDataInFinder() {
    guard case let .unavailable(_, dataURL) = localStoreAvailability, let dataURL else { return }
    let target = FileManager.default.fileExists(atPath: dataURL.path)
      ? dataURL : dataURL.deletingLastPathComponent()
    NSWorkspace.shared.activateFileViewerSelecting([target])
  }

  func moveSelection(_ delta: Int) {
    guard !reminders.isEmpty else { return }
    let currentIndex = reminders.firstIndex { $0.id == selectedReminderID } ?? 0
    let nextIndex = min(max(currentIndex + delta, 0), reminders.count - 1)
    selectedReminderID = reminders[nextIndex].id
  }

  func setIslandHovered(_ hovering: Bool) {
    guard isPointerInsideIsland != hovering else { return }
    isPointerInsideIsland = hovering
    hoverTask?.cancel()

    if hovering {
      guard islandState == .collapsed else { return }
      if suspendedEditingFocus != nil {
        pinIsland()
        return
      }
      hoverTask = Task {
        try? await Task.sleep(for: .milliseconds(200))
        guard
          !Task.isCancelled,
          isPointerInsideIsland,
          islandState == .collapsed
        else { return }
        islandState = .preview
      }
    } else {
      schedulePointerExitCollapseIfNeeded()
    }
  }

  func setQuickAddActive(_ active: Bool) {
    guard isQuickAddActive != active else { return }
    isQuickAddActive = active
  }

  func pinIsland() {
    hoverTask?.cancel()
    islandState = .pinned
    guard let suspendedEditingFocus else { return }
    self.suspendedEditingFocus = nil
    switch suspendedEditingFocus {
    case .quickAdd:
      quickAddFocusRequestID = UUID()
    case .reminderEditor:
      editingFocusRequestID = UUID()
    }
  }

  func collapseIsland() {
    hoverTask?.cancel()
    suspendedEditingFocus = nil
    isPointerInsideIsland = false
    isQuickAddActive = false
    if editingReminderID == nil
      || reminders.first(where: { $0.id == editingReminderID }).map({ canAccess(source: $0.source) })
        == true
    {
      cancelEditing()
    }
    islandState = .collapsed
  }

  func setHostDisplayID(_ displayID: String?) {
    hostDisplayID = displayID
  }

  func markApplicationActive() {
    let newAuthorization = store.authorizationStatus()
    authorization = newAuthorization
    localStoreAvailability = store.localStoreAvailability
    scheduleRefresh(delay: .milliseconds(50))
    if newAuthorization != .fullAccess,
      let editingReminderID,
      reminders.first(where: { $0.id == editingReminderID })?.source == .iCloud
    {
      isEditingDraftValidated = false
    }
  }

  private func scheduleRefresh(delay: Duration = .milliseconds(250)) {
    refreshTask?.cancel()
    refreshTask = Task {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await reload()
    }
  }

  private func schedulePointerExitCollapseIfNeeded() {
    guard !isPointerInsideIsland, shouldCollapseAfterPointerExit else { return }
    let delay: Duration = islandState == .pinned ? .milliseconds(200) : .milliseconds(500)
    hoverTask?.cancel()
    hoverTask = Task {
      try? await Task.sleep(for: delay)
      guard
        !Task.isCancelled,
        !isPointerInsideIsland,
        shouldCollapseAfterPointerExit
      else { return }
      if islandState == .pinned {
        suspendPinnedIsland()
      } else {
        collapseIsland()
      }
    }
  }

  private var shouldCollapseAfterPointerExit: Bool {
    islandState == .preview || (islandState == .pinned && canUseActiveList)
  }

  private func suspendPinnedIsland() {
    if isQuickAddActive
      || !quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      suspendedEditingFocus = .quickAdd
    } else if editingReminderID != nil, draft != nil {
      suspendedEditingFocus = .reminderEditor
    } else {
      suspendedEditingFocus = nil
    }

    isQuickAddActive = false
    islandState = .collapsed
  }

  private func removeCompletedReminder(id: String) {
    let removedIndex = reminders.firstIndex { $0.id == id }
    reminders.removeAll { $0.id == id }
    completingReminderIDs.remove(id)

    guard selectedReminderID == id else { return }
    guard let removedIndex, !reminders.isEmpty else {
      selectedReminderID = nil
      return
    }
    selectedReminderID = reminders[min(removedIndex, reminders.count - 1)].id
  }

  private func present(_ error: Error) {
    errorMessage = error.localizedDescription
  }

  private func canAccess(source: ReminderSource) -> Bool {
    switch source {
    case .iCloud: authorization == .fullAccess
    case .local: localStoreAvailability == .available
    }
  }
}
