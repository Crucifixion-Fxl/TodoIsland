import Foundation

enum ReminderSorter {
  static func sorted(
    _ reminders: [ReminderSnapshot],
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [ReminderSnapshot] {
    reminders.sorted { lhs, rhs in
      let left = key(for: lhs, now: now, calendar: calendar)
      let right = key(for: rhs, now: now, calendar: calendar)

      if left.group != right.group { return left.group < right.group }
      if left.date != right.date { return left.date < right.date }
      if lhs.priority.sortRank != rhs.priority.sortRank {
        return lhs.priority.sortRank < rhs.priority.sortRank
      }
      let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
      if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
      return lhs.id < rhs.id
    }
  }

  private static func key(
    for reminder: ReminderSnapshot,
    now: Date,
    calendar: Calendar
  ) -> (group: Int, date: Date) {
    guard let dueDate = reminder.dueDate(in: calendar) else {
      return (3, .distantFuture)
    }

    let today = calendar.startOfDay(for: now)
    let dueDay = calendar.startOfDay(for: dueDate)
    if dueDay < today { return (0, dueDate) }
    if calendar.isDate(dueDate, inSameDayAs: now) { return (1, dueDate) }
    return (2, dueDate)
  }
}
