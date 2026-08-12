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
  @Published private(set) var completingReminderIDs: Set<String> = []
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
  @Published var selectedDisplayID: String? {
    didSet {
      defaults.set(selectedDisplayID, forKey: Keys.selectedDisplayID)
    }
  }
  @Published private(set) var displays: [DisplaySnapshot] = []

  private let store: ReminderStore
  private let defaults: UserDefaults
  private var refreshTask: Task<Void, Never>?
  private var hoverTask: Task<Void, Never>?
  private var isPointerInsideIsland = false

  private enum Keys {
    static let activeListID = "active-list-id"
    static let selectedDisplayID = "selected-display-id"
    static let completedOnboarding = "completed-onboarding"
  }

  init(
    store: ReminderStore = EventKitReminderStore(),
    defaults: UserDefaults = .standard
  ) {
    self.store = store
    self.defaults = defaults
    authorization = store.authorizationStatus()
    activeListID = defaults.string(forKey: Keys.activeListID)
    selectedDisplayID = defaults.string(forKey: Keys.selectedDisplayID)

    store.onStoreChanged = { [weak self] in
      self?.scheduleRefresh()
    }
  }

  var activeList: ReminderListSnapshot? {
    lists.first { $0.id == activeListID }
  }

  var nextReminder: ReminderSnapshot? { reminders.first }
  var remainingCount: Int { reminders.count }
  var hasCompletedOnboarding: Bool { defaults.bool(forKey: Keys.completedOnboarding) }

  func start() async {
    reloadDisplays()
    authorization = store.authorizationStatus()
    if authorization == .fullAccess {
      await reload()
    }
  }

  func requestAccess() async {
    do {
      _ = try await store.requestFullAccess()
      authorization = store.authorizationStatus()
      if authorization == .fullAccess { await reload() }
    } catch {
      present(error)
      authorization = store.authorizationStatus()
    }
  }

  func completeOnboarding() {
    defaults.set(true, forKey: Keys.completedOnboarding)
  }

  func reload() async {
    guard authorization == .fullAccess else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let newLists = try await store.fetchLists()
      lists = newLists

      if !newLists.contains(where: { $0.id == activeListID }) {
        activeListID = newLists.first?.id
      }

      guard let activeListID else {
        reminders = []
        selectedReminderID = nil
        return
      }

      let fetched = try await store.fetchPendingReminders(in: activeListID)
      reminders = ReminderSorter.sorted(fetched)
      if !reminders.contains(where: { $0.id == selectedReminderID }) {
        selectedReminderID = reminders.first?.id
      }
    } catch {
      present(error)
    }
  }

  func selectList(_ id: String) {
    guard lists.contains(where: { $0.id == id }) else { return }
    activeListID = id
    selectedReminderID = nil
    editingReminderID = nil
    draft = nil
    Task { await reload() }
  }

  func createQuickReminder() {
    let title = quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, let activeListID else { return }
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
    selectedReminderID = reminder.id
    editingReminderID = reminder.id
    draft = ReminderDraft(reminder: reminder)
  }

  func cancelEditing() {
    editingReminderID = nil
    draft = nil
  }

  func saveEditing() {
    guard let id = editingReminderID, let draft else { return }
    guard !draft.normalizedTitle.isEmpty else {
      errorMessage = ReminderStoreError.emptyTitle.localizedDescription
      return
    }

    editingReminderID = nil
    self.draft = nil
    Task {
      do {
        try await store.updateReminder(id: id, from: draft)
        await reload()
      } catch {
        present(error)
      }
    }
  }

  func complete(_ reminder: ReminderSnapshot) {
    guard
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
      guard islandState == .preview else { return }
      hoverTask = Task {
        try? await Task.sleep(for: .milliseconds(500))
        guard
          !Task.isCancelled,
          !isPointerInsideIsland,
          islandState == .preview
        else { return }
        islandState = .collapsed
      }
    }
  }

  func pinIsland() {
    hoverTask?.cancel()
    islandState = .pinned
  }

  func collapseIsland() {
    hoverTask?.cancel()
    isPointerInsideIsland = false
    cancelEditing()
    islandState = .collapsed
  }

  func reloadDisplays() {
    displays = DisplaySupport.snapshots()
    if !displays.contains(where: { $0.id == selectedDisplayID }) {
      selectedDisplayID = displays.first(where: \.hasPhysicalNotch)?.id ?? displays.first?.id
    }
  }

  func markApplicationActive() {
    authorization = store.authorizationStatus()
    if authorization == .fullAccess { scheduleRefresh(delay: .milliseconds(50)) }
  }

  private func scheduleRefresh(delay: Duration = .milliseconds(250)) {
    refreshTask?.cancel()
    refreshTask = Task {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await reload()
    }
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
