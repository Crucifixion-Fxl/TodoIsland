import AppKit
import SwiftUI

struct IslandRootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var quickAddFocused: Bool
  @FocusState private var editorTitleFocused: Bool
  @State private var reminderPendingDeletion: ReminderSnapshot?
  @State private var focusQuickAddAfterPinning = false

  private var isPinned: Bool { model.islandState == .pinned }

  var body: some View {
    GeometryReader { proxy in
      let surfaceSize = IslandAnimatedSurfaceLayout.surfaceSize(
        windowSize: proxy.size,
        targetSize: islandSurfaceSize
      )

      Group {
        if model.islandState == .collapsed {
          collapsedContent
        } else {
          expandedContent
        }
      }
      .frame(width: surfaceSize.width, height: surfaceSize.height, alignment: .top)
      .background(.black)
      .clipShape(islandShape)
      .overlay(alignment: .top) {
        Rectangle().fill(.black).frame(height: 1).padding(
          .horizontal, model.islandState == .collapsed ? 6 : 10)
      }
      .contentShape(Rectangle())
      .onHover { hovering in
        model.setIslandHovered(hovering)
      }
      .onTapGesture {
        if !isPinned { model.pinIsland() }
      }
      .background(KeyboardEventMonitor(handler: handleKeyEvent))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .confirmationDialog(
        L10n.text("delete.title"),
        isPresented: Binding(
          get: { reminderPendingDeletion != nil },
          set: { if !$0 { reminderPendingDeletion = nil } }
        )
      ) {
        Button(L10n.text("delete.confirm"), role: .destructive) {
          if let reminderPendingDeletion { model.delete(reminderPendingDeletion) }
          reminderPendingDeletion = nil
        }
        Button(L10n.text("common.cancel"), role: .cancel) {
          reminderPendingDeletion = nil
        }
      } message: {
        Text(reminderPendingDeletion?.title ?? "")
      }
      .alert(
        L10n.text("error.title"),
        isPresented: Binding(
          get: { model.errorMessage != nil },
          set: { if !$0 { model.errorMessage = nil } }
        )
      ) {
        Button(L10n.text("common.ok")) { model.errorMessage = nil }
      } message: {
        Text(model.errorMessage ?? "")
      }
      .onChange(of: model.editingReminderID) { _, id in
        if id != nil { editorTitleFocused = true }
      }
      .onChange(of: model.islandState) { _, state in
        guard state == .pinned, focusQuickAddAfterPinning else { return }
        focusQuickAddAfterPinning = false
        Task { @MainActor in quickAddFocused = true }
      }
    }
  }

  private var islandShape: UnevenRoundedRectangle {
    if model.islandState == .collapsed {
      UnevenRoundedRectangle(
        topLeadingRadius: 6,
        bottomLeadingRadius: 14,
        bottomTrailingRadius: 14,
        topTrailingRadius: 6
      )
    } else {
      UnevenRoundedRectangle(
        topLeadingRadius: 10,
        bottomLeadingRadius: 24,
        bottomTrailingRadius: 24,
        topTrailingRadius: 10
      )
    }
  }

  @ViewBuilder
  private var collapsedContent: some View {
    if model.authorization != .fullAccess {
      HStack(spacing: 8) {
        Image(systemName: "lock.fill")
        Text("island.locked")
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(maxHeight: .infinity)
      .accessibilityLabel(Text("island.locked.accessibility"))
    } else if hostDisplayHasNotch {
      HStack(spacing: 0) {
        Text(model.activeList?.title ?? L10n.text("list.none"))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
          .frame(width: collapsedSideContentWidth, alignment: .leading)
          .padding(.leading, collapsedOuterInset)

        Color.clear
          .frame(width: hostPhysicalNotchWidth)

        remainingCountRing
          .frame(width: collapsedSideContentWidth, alignment: .trailing)
          .padding(.trailing, collapsedOuterInset)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(collapsedAccessibilityLabel)
    } else {
      HStack(spacing: 8) {
        Text(model.activeList?.title ?? L10n.text("list.none"))
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 4)
        remainingCountRing
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(maxHeight: .infinity)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(collapsedAccessibilityLabel)
    }
  }

  private var expandedContent: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(.white.opacity(0.12))

      if model.authorization == .fullAccess {
        reminderContent
      } else {
        lockedContent
      }

      if model.islandState.showsQuickAdd && model.authorization == .fullAccess
        && !model.lists.isEmpty
      {
        quickAdd
      }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .padding(.top, 10)
    .padding(.bottom, 14)
  }

  private var header: some View {
    HStack(spacing: 10) {
      if model.authorization == .fullAccess {
        Menu {
          ForEach(model.lists) { list in
            Button {
              model.selectList(list.id)
            } label: {
              if list.id == model.activeListID {
                Label(list.title, systemImage: "checkmark")
              } else {
                Text(list.title)
              }
            }
          }
        } label: {
          HStack(spacing: 7) {
            Circle().fill(accentColor).frame(width: 8, height: 8)
            Text(model.activeList?.title ?? L10n.text("list.none"))
              .font(.headline)
              .lineLimit(1)
            Image(systemName: "chevron.down")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text("list.switch"))
      } else {
        HStack(spacing: 7) {
          Circle().fill(accentColor).frame(width: 8, height: 8)
          Text(model.activeList?.title ?? L10n.text("app.name"))
            .font(.headline)
            .lineLimit(1)
        }
      }

      Spacer()

      if model.isLoading {
        ProgressView().controlSize(.small)
      } else if model.authorization == .fullAccess {
        Text("\(model.remainingCount)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel(
            Text(String(format: L10n.text("reminders.remaining"), model.remainingCount)))
      }

      if isPinned {
        Button {
          model.collapseIsland()
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("island.close"))
      }
    }
    .frame(height: 30)
  }

  @ViewBuilder
  private var reminderContent: some View {
    if model.lists.isEmpty {
      noListsContent
    } else if model.reminders.isEmpty {
      centeredMessage(
        icon: "checkmark.circle.fill", title: "island.all-done", detail: "all-done.detail")
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 5) {
            ForEach(model.reminders) { reminder in
              reminderRow(reminder)
                .id(reminder.id)
              if model.editingReminderID == reminder.id, let draft = model.draft {
                reminderEditor(draft)
                  .transition(.opacity.combined(with: .move(edge: .top)))
              }
            }
          }
          .padding(.vertical, 8)
        }
        .onChange(of: model.selectedReminderID) { _, id in
          guard let id else { return }
          withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
            proxy.scrollTo(id, anchor: .center)
          }
        }
      }
    }
  }

  private func reminderRow(_ reminder: ReminderSnapshot) -> some View {
    let isCompleting = model.completingReminderIDs.contains(reminder.id)

    return HStack(spacing: 10) {
      Button {
        model.complete(reminder)
      } label: {
        Image(systemName: isCompleting ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(isCompleting ? Color.green : accentColor)
      }
      .buttonStyle(.plain)
      .disabled(isCompleting)
      .accessibilityLabel(Text(String(format: L10n.text("reminder.complete"), reminder.title)))

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(reminder.title)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
          if reminder.isRecurring {
            Image(systemName: "repeat")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .accessibilityLabel(Text("reminder.recurring"))
          }
        }

        if let due = dueLabel(for: reminder) {
          Text(due.text)
            .font(.caption)
            .foregroundStyle(due.isOverdue ? .red : .secondary)
        }
      }

      Spacer(minLength: 8)

      if reminder.priority != .none {
        Image(systemName: prioritySymbol(reminder.priority))
          .font(.caption)
          .foregroundStyle(priorityColor(reminder.priority))
          .accessibilityLabel(priorityLabel(reminder.priority))
      }

      if isPinned {
        Menu {
          Button(L10n.text("reminder.edit")) { model.beginEditing(reminder) }
          Divider()
          Button(L10n.text("reminder.delete"), role: .destructive) {
            reminderPendingDeletion = reminder
          }
        } label: {
          Image(systemName: "ellipsis")
            .frame(width: 22, height: 22)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(Text(String(format: L10n.text("reminder.actions"), reminder.title)))
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background {
      RoundedRectangle(cornerRadius: 10)
        .fill(
          model.selectedReminderID == reminder.id
            ? accentColor.opacity(0.18) : .white.opacity(0.045))
    }
    .contentShape(Rectangle())
    .onTapGesture {
      guard isPinned else { return }
      model.selectedReminderID = reminder.id
    }
    .onTapGesture(count: 2) {
      guard isPinned else { return }
      model.beginEditing(reminder)
    }
    .accessibilityElement(children: .contain)
  }

  private func reminderEditor(_ draft: ReminderDraft) -> some View {
    VStack(spacing: 10) {
      TextField(
        L10n.text("editor.title.placeholder"),
        text: Binding(
          get: { model.draft?.title ?? "" },
          set: { model.draft?.title = $0 }
        )
      )
      .textFieldStyle(.roundedBorder)
      .focused($editorTitleFocused)
      .onSubmit { model.saveEditing() }

      HStack(spacing: 12) {
        Toggle(
          L10n.text("editor.due-date"),
          isOn: Binding(
            get: { model.draft?.hasDueDate ?? false },
            set: { model.draft?.hasDueDate = $0 }
          )
        )
        .toggleStyle(.switch)
        .controlSize(.small)

        if model.draft?.hasDueDate == true {
          DatePicker(
            "",
            selection: Binding(
              get: { model.draft?.dueDate ?? Date() },
              set: { model.draft?.dueDate = $0 }
            ),
            displayedComponents: model.draft?.includesTime == true
              ? [.date, .hourAndMinute] : [.date]
          )
          .labelsHidden()
          .controlSize(.small)

          Toggle(
            L10n.text("editor.time"),
            isOn: Binding(
              get: { model.draft?.includesTime ?? false },
              set: { model.draft?.includesTime = $0 }
            )
          )
          .toggleStyle(.checkbox)
          .controlSize(.small)
        }
      }

      HStack {
        Picker(
          L10n.text("editor.priority"),
          selection: Binding(
            get: { model.draft?.priority ?? .none },
            set: { model.draft?.priority = $0 }
          )
        ) {
          Text("priority.none").tag(ReminderPriority.none)
          Text("priority.low").tag(ReminderPriority.low)
          Text("priority.medium").tag(ReminderPriority.medium)
          Text("priority.high").tag(ReminderPriority.high)
        }
        .pickerStyle(.segmented)

        Button(L10n.text("common.cancel")) { model.cancelEditing() }
        Button(L10n.text("common.save")) { model.saveEditing() }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canSaveEditingDraft)
      }
    }
    .padding(10)
    .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
  }

  private var quickAdd: some View {
    HStack(spacing: 8) {
      Image(systemName: "plus.circle.fill")
        .foregroundStyle(accentColor)
      TextField("quick-add.placeholder", text: $model.quickAddTitle)
        .textFieldStyle(.plain)
        .focused($quickAddFocused)
        .onSubmit { model.createQuickReminder() }
        .accessibilityLabel(Text("quick-add.accessibility"))
      Button {
        model.createQuickReminder()
      } label: {
        Image(systemName: "arrow.up.circle.fill")
      }
      .buttonStyle(.plain)
      .foregroundStyle(accentColor)
      .disabled(model.quickAddTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityLabel(Text("quick-add.submit"))
    }
    .padding(.horizontal, 10)
    .frame(height: 38)
    .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.08)))
    .contentShape(Rectangle())
    .simultaneousGesture(
      TapGesture().onEnded {
        if isPinned {
          quickAddFocused = true
        } else {
          focusQuickAddAfterPinning = true
          model.pinIsland()
        }
      }
    )
  }

  private var lockedContent: some View {
    VStack(spacing: 12) {
      Image(systemName: "lock.shield.fill")
        .font(.system(size: 34))
        .foregroundStyle(accentColor)
      Text("permission.required")
        .font(.headline)
      Text("permission.required.detail")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Text("permission.privacy")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      if isPinned {
        if model.isRequestingAccess {
          ProgressView()
            .controlSize(.small)
            .tint(accentColor)
        } else {
          Button(
            L10n.text(
              model.authorization == .notDetermined
                ? "permission.allow"
                : "permission.open-settings")
          ) {
            if model.authorization == .notDetermined {
              Task { await model.requestAccess() }
            } else {
              SystemSettings.openRemindersPrivacy()
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(accentColor)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var noListsContent: some View {
    VStack(spacing: 10) {
      Image(systemName: "list.bullet")
        .font(.system(size: 30))
        .foregroundStyle(accentColor)
      Text("list.no-icloud").font(.headline)
      Text("list.no-icloud.detail")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      if isPinned {
        HStack(spacing: 10) {
          Button("list.open-reminders") {
            SystemSettings.openReminders()
          }
          Button("list.check-again") {
            Task { await model.reload() }
          }
          .buttonStyle(.borderedProminent)
          .tint(accentColor)
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(20)
  }

  private func centeredMessage(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey)
    -> some View
  {
    VStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 30))
        .foregroundStyle(accentColor)
      Text(title).font(.headline)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(20)
  }

  private var accentColor: Color {
    let accent = model.activeList?.accent ?? .fallback
    return Color(
      .sRGB, red: accent.red, green: accent.green, blue: accent.blue, opacity: accent.alpha)
  }

  private var hostDisplayHasNotch: Bool {
    guard let screen = DisplaySupport.screen(id: model.hostDisplayID) else { return false }
    return DisplaySupport.metrics(for: screen).hasPhysicalNotch
  }

  private var hostPhysicalNotchWidth: CGFloat {
    guard let screen = DisplaySupport.screen(id: model.hostDisplayID) else { return 0 }
    return DisplaySupport.metrics(for: screen).physicalNotchWidth
  }

  private var collapsedSideWidth: CGFloat {
    max(0, (islandSurfaceSize.width - hostPhysicalNotchWidth) / 2)
  }

  private var collapsedOuterInset: CGFloat { 12 }

  private var collapsedSideContentWidth: CGFloat {
    max(0, collapsedSideWidth - collapsedOuterInset)
  }

  private var islandSurfaceSize: CGSize {
    guard let screen = DisplaySupport.screen(id: model.hostDisplayID) else { return .zero }
    return DisplayGeometryCalculator.geometry(for: DisplaySupport.metrics(for: screen))
      .size(for: model.islandState)
  }

  private var collapsedAccessibilityLabel: Text {
    Text(
      String(
        format: L10n.text("island.collapsed.accessibility"),
        model.activeList?.title ?? L10n.text("list.none"),
        model.remainingCount))
  }

  private var remainingCountRing: some View {
    ZStack {
      Circle()
        .stroke(.green, lineWidth: 1.5)
      Text("\(model.remainingCount)")
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .foregroundStyle(.blue)
        .monospacedDigit()
        .minimumScaleFactor(0.7)
        .padding(2)
    }
    .frame(width: 18, height: 18)
  }

  private func dueLabel(for reminder: ReminderSnapshot) -> (text: String, isOverdue: Bool)? {
    guard let date = reminder.dueDate(in: .current) else { return nil }
    let calendar = Calendar.current
    let isOverdue = calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = calendar.isDateInToday(date) ? .none : .medium
    formatter.timeStyle = reminder.dueDateComponents?.hour == nil ? .none : .short
    let value =
      calendar.isDateInToday(date) && reminder.dueDateComponents?.hour == nil
      ? L10n.text("date.today")
      : formatter.string(from: date)
    return (value, isOverdue)
  }

  private func prioritySymbol(_ priority: ReminderPriority) -> String {
    switch priority {
    case .high: "exclamationmark.3"
    case .medium: "exclamationmark.2"
    case .low: "exclamationmark"
    case .none: ""
    }
  }

  private func priorityColor(_ priority: ReminderPriority) -> Color {
    switch priority {
    case .high: .red
    case .medium: .orange
    case .low: .yellow
    case .none: .secondary
    }
  }

  private func priorityLabel(_ priority: ReminderPriority) -> Text {
    switch priority {
    case .high: Text("priority.high")
    case .medium: Text("priority.medium")
    case .low: Text("priority.low")
    case .none: Text("priority.none")
    }
  }

  private func handleKeyEvent(_ event: NSEvent) -> Bool {
    guard isPinned else { return false }

    if event.modifierFlags.contains(.command),
      event.charactersIgnoringModifiers?.lowercased() == "n"
    {
      quickAddFocused = true
      return true
    }

    let isEditingText = NSApp.keyWindow?.firstResponder is NSTextView
    if event.keyCode == 53 {
      if model.authorization == .fullAccess, model.editingReminderID != nil {
        model.cancelEditing()
      } else {
        model.collapseIsland()
      }
      return true
    }
    if isEditingText { return false }

    switch event.keyCode {
    case 125:
      model.moveSelection(1)
      return true
    case 126:
      model.moveSelection(-1)
      return true
    case 36:
      if let selected = model.reminders.first(where: { $0.id == model.selectedReminderID }) {
        model.beginEditing(selected)
        return true
      }
    case 49:
      if let selected = model.reminders.first(where: { $0.id == model.selectedReminderID }) {
        model.complete(selected)
        return true
      }
    case 51, 117:
      if let selected = model.reminders.first(where: { $0.id == model.selectedReminderID }) {
        reminderPendingDeletion = selected
        return true
      }
    default:
      break
    }
    return false
  }
}
