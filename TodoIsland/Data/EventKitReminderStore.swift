import AppKit
@preconcurrency import EventKit
import Foundation

@MainActor
final class EventKitReminderStore: ReminderStore {
  var onStoreChanged: (() -> Void)?

  private let eventStore: EKEventStore
  private var changeObserver: NSObjectProtocol?

  init(eventStore: EKEventStore = EKEventStore()) {
    self.eventStore = eventStore
    changeObserver = NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.onStoreChanged?()
      }
    }
  }

  isolated deinit {
    if let changeObserver {
      NotificationCenter.default.removeObserver(changeObserver)
    }
  }

  func authorizationStatus() -> ReminderAuthorization {
    switch EKEventStore.authorizationStatus(for: .reminder) {
    case .notDetermined: .notDetermined
    case .restricted: .restricted
    case .denied: .denied
    case .fullAccess, .authorized: .fullAccess
    case .writeOnly: .denied
    @unknown default: .denied
    }
  }

  func requestFullAccess() async throws -> Bool {
    let granted = try await eventStore.requestFullAccessToReminders()
    if granted { eventStore.reset() }
    return granted
  }

  func fetchLists() async throws -> [ReminderListSnapshot] {
    eventStore.calendars(for: .reminder)
      .filter(Self.isICloudCalendar)
      .map(Self.snapshot)
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  func fetchPendingReminders(in listID: String) async throws -> [ReminderSnapshot] {
    guard let calendar = reminderCalendar(id: listID) else {
      throw ReminderStoreError.listNotFound
    }
    let predicate = eventStore.predicateForIncompleteReminders(
      withDueDateStarting: nil,
      ending: nil,
      calendars: [calendar]
    )

    return try await withCheckedThrowingContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        DispatchQueue.main.async {
          let snapshots = (reminders ?? []).map(Self.snapshot)
          continuation.resume(returning: snapshots)
        }
      }
    }
  }

  func createReminder(title: String, in listID: String) async throws {
    let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { throw ReminderStoreError.emptyTitle }
    guard let calendar = reminderCalendar(id: listID) else {
      throw ReminderStoreError.listNotFound
    }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = calendar
    reminder.title = normalized
    reminder.priority = ReminderPriority.none.rawValue
    try eventStore.save(reminder, commit: true)
  }

  func updateReminder(id: String, from draft: ReminderDraft) async throws {
    guard !draft.normalizedTitle.isEmpty else { throw ReminderStoreError.emptyTitle }
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      throw ReminderStoreError.reminderNotFound
    }

    reminder.title = draft.normalizedTitle
    reminder.dueDateComponents = draft.dueComponents()
    reminder.priority = draft.priority.rawValue
    try eventStore.save(reminder, commit: true)
  }

  func setCompleted(_ completed: Bool, reminderID: String) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
      throw ReminderStoreError.reminderNotFound
    }
    reminder.isCompleted = completed
    try eventStore.save(reminder, commit: true)
  }

  func deleteReminder(id: String) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      throw ReminderStoreError.reminderNotFound
    }
    try eventStore.remove(reminder, commit: true)
  }

  private func reminderCalendar(id: String) -> EKCalendar? {
    eventStore.calendars(for: .reminder)
      .first { $0.calendarIdentifier == id && Self.isICloudCalendar($0) }
  }

  private static func isICloudCalendar(_ calendar: EKCalendar) -> Bool {
    calendar.source.sourceType == .calDAV
      && calendar.source.title.range(of: "icloud", options: .caseInsensitive) != nil
  }

  private static func snapshot(_ calendar: EKCalendar) -> ReminderListSnapshot {
    ReminderListSnapshot(
      id: calendar.calendarIdentifier,
      title: calendar.title,
      accent: accent(from: calendar.cgColor)
    )
  }

  private static func snapshot(_ reminder: EKReminder) -> ReminderSnapshot {
    ReminderSnapshot(
      id: reminder.calendarItemIdentifier,
      listID: reminder.calendar.calendarIdentifier,
      title: reminder.title,
      dueDateComponents: reminder.dueDateComponents,
      priority: ReminderPriority(eventKitValue: reminder.priority),
      isRecurring: !(reminder.recurrenceRules?.isEmpty ?? true)
    )
  }

  private static func accent(from cgColor: CGColor?) -> AccentSnapshot {
    guard
      let cgColor,
      let color = NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB)
    else { return .fallback }

    return AccentSnapshot(
      red: Double(color.redComponent),
      green: Double(color.greenComponent),
      blue: Double(color.blueComponent),
      alpha: Double(color.alphaComponent)
    )
  }
}
