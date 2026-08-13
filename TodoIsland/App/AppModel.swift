import AppKit
import Combine
import Foundation

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

  private enum Keys {
    static let activeListID = "active-list-id"
  }

  init(
    store: ReminderStore = EventKitReminderStore(),
    defaults: UserDefaults = .standard
  ) {
    self.store = store
    self.defaults = defaults
    authorization = store.authorizationStatus()
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

  var nextReminder: ReminderSnapshot? { reminders.first }
  var remainingCount: Int { reminders.count }
  var canSaveEditingDraft: Bool {
    guard
      authorization == .fullAccess,
      isEditingDraftValidated,
      let editingReminderID,
      draft != nil
    else { return false }
    return reminders.contains { $0.id == editingReminderID }
  }

  func start() async {
    authorization = store.authorizationStatus()
    if authorization == .fullAccess {
      await reload()
    } else if authorization == .notDetermined {
      pinIsland()
    }
  }

  func requestAccess() async {
    guard authorization == .notDetermined, !isRequestingAccess else { return }
    isRequestingAccess = true
    defer { isRequestingAccess = false }

    do {
      _ = try await store.requestFullAccess()
      authorization = store.authorizationStatus()
      if authorization == .fullAccess { await reload() }
    } catch {
      present(error)
      authorization = store.authorizationStatus()
    }
  }

  func reload() async {
    guard authorization == .fullAccess else { return }
    isLoading = true
    defer {
      isLoading = false
      schedulePointerExitCollapseIfNeeded()
    }

    do {
      let newLists = try await store.fetchLists()
      lists = newLists

      if !newLists.contains(where: { $0.id == activeListID }) {
        activeListID = newLists.first?.id
      }

      guard let activeListID else {
        reminders = []
        selectedReminderID = nil
        isEditingDraftValidated = editingReminderID == nil
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
    guard authorization == .fullAccess, lists.contains(where: { $0.id == id }) else { return }
    activeListID = id
    selectedReminderID = nil
    cancelEditing()
    Task { await reload() }
  }

  func createQuickReminder() {
    let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard authorization == .fullAccess, !title.isEmpty, let activeListID else { return }
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
    guard authorization == .fullAccess else { return }
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
    guard authorization == .fullAccess, isEditingDraftValidated else { return }
    guard reminders.contains(where: { $0.id == id }) else {
      errorMessage = ReminderStoreError.reminderNotFound.localizedDescription
      return
    }
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
      authorization == .fullAccess,
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
    guard authorization == .fullAccess else { return }
    Task {
      do {
        try await store.deleteReminder(id: reminder.id)
        await reload()
      } catch {
        present(error)
      }
    }
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
    hoverTask?.cancel()
    if !active {
      schedulePointerExitCollapseIfNeeded()
    }
  }

  func pinIsland() {
    hoverTask?.cancel()
    islandState = .pinned
  }

  func collapseIsland() {
    hoverTask?.cancel()
    isPointerInsideIsland = false
    isQuickAddActive = false
    if authorization == .fullAccess {
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
    if newAuthorization == .fullAccess {
      scheduleRefresh(delay: .milliseconds(50))
    } else {
      refreshTask?.cancel()
      isLoading = false
      if draft != nil {
        isEditingDraftValidated = false
      }
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
    hoverTask?.cancel()
    hoverTask = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard
        !Task.isCancelled,
        !isPointerInsideIsland,
        shouldCollapseAfterPointerExit
      else { return }
      collapseIsland()
    }
  }

  private var shouldCollapseAfterPointerExit: Bool {
    if islandState == .preview { return true }
    guard
      islandState == .pinned,
      authorization == .fullAccess,
      activeListID != nil,
      !isLoading,
      reminders.isEmpty,
      editingReminderID == nil,
      !isQuickAddActive,
      quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return false }
    return true
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
}
