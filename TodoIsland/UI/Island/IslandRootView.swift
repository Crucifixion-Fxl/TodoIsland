import AppKit
import SwiftUI

struct IslandRootView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @FocusState private var quickAddFocused: Bool
  @FocusState private var editorTitleFocused: Bool
  @FocusState private var listNameFocused: Bool
  @State private var reminderPendingDeletion: ReminderSnapshot?
  @State private var listPendingRename: ReminderListSnapshot?
  @State private var listNameDraft = ""
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
      .confirmationDialog(
        L10n.text("list.delete.title"),
        isPresented: Binding(
          get: { model.listDeletionCandidate != nil },
          set: { if !$0 { model.cancelListDeletion() } }
        )
      ) {
        Button(L10n.text("list.delete.confirm"), role: .destructive) {
          Task { await model.confirmListDeletion() }
        }
        Button(L10n.text("common.cancel"), role: .cancel) {
          model.cancelListDeletion()
        }
      } message: {
        if let candidate = model.listDeletionCandidate {
          Text(
            String(
              format: L10n.text("list.delete.detail"),
              candidate.list.title,
              candidate.pendingCount,
              candidate.completedCount
            ))
        }
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
      .onChange(of: quickAddFocused) { _, focused in
        model.setQuickAddActive(focused)
      }
      .onChange(of: model.quickAddFocusRequestID) { _, _ in
        Task { @MainActor in quickAddFocused = true }
      }
      .onChange(of: model.requestedListCreationSource) { _, source in
        guard source != nil else { return }
        listPendingRename = nil
        listNameDraft = ""
        Task { @MainActor in listNameFocused = true }
      }
      .onChange(of: model.islandState) { _, state in
        if state == .collapsed {
          quickAddFocused = false
          return
        }
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
    if !model.canUseActiveList {
      HStack(spacing: 8) {
        Image(systemName: model.authorization == .fullAccess ? "list.bullet" : "lock.fill")
        Text(model.authorization == .fullAccess ? "list.none" : "island.locked")
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(maxHeight: .infinity)
      .accessibilityLabel(
        Text(model.authorization == .fullAccess ? "list.none" : "island.locked.accessibility"))
    } else if hostDisplayHasNotch {
      HStack(spacing: 0) {
        HStack(spacing: 4) {
          sourceGlyph
          Text(model.activeList?.title ?? L10n.text("list.none"))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
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
        sourceGlyph
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

      if model.requestedListCreationSource != nil {
        listCreationForm
      } else if listPendingRename != nil {
        listRenameForm
      } else if model.canUseActiveList {
        reminderContent
      } else if model.preferredEmptySource == .local,
        model.localStoreAvailability == .available
      {
        localEmptyContent
      } else if case .unavailable = model.localStoreAvailability,
        model.authorization == .fullAccess
      {
        localStoreUnavailableContent
      } else if model.authorization == .fullAccess {
        noListsContent
      } else {
        lockedContent
      }

      if model.islandState.showsQuickAdd && model.canUseActiveList
        && model.requestedListCreationSource == nil && listPendingRename == nil
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
      Menu {
        if !model.iCloudLists.isEmpty {
          Section(L10n.text("source.icloud")) {
            ForEach(model.iCloudLists) { list in
              listSelectionButton(list)
            }
          }
        }

        Section(L10n.text("source.local")) {
          ForEach(model.localLists) { list in
            Menu(list.title) {
              Button {
                model.selectList(list.id)
              } label: {
                Label(
                  list.id == model.activeListID
                    ? L10n.text("list.active") : L10n.text("list.open"),
                  systemImage: list.id == model.activeListID ? "checkmark" : "arrow.right"
                )
              }
              Button(L10n.text("list.rename")) {
                model.cancelListCreation()
                listPendingRename = list
                listNameDraft = list.title
                Task { @MainActor in listNameFocused = true }
              }
              Divider()
              Button(L10n.text("list.delete"), role: .destructive) {
                Task { await model.prepareListDeletion(list) }
              }
            }
          }
          if model.localLists.isEmpty {
            Button {
              Task { await model.useLocal() }
            } label: {
              Label(L10n.text("source.use-local"), systemImage: "desktopcomputer")
            }
          }
        }

        Divider()
        Button {
          listPendingRename = nil
          model.requestNewList()
        } label: {
          Label(L10n.text("list.new"), systemImage: "plus")
        }
      } label: {
        HStack(spacing: 7) {
          Circle().fill(accentColor).frame(width: 8, height: 8)
          if let activeList = model.activeList {
            Image(systemName: activeList.source.symbolName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
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

      Spacer()

      if model.isLoading {
        ProgressView().controlSize(.small)
      } else if model.canUseActiveList {
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

  private func listSelectionButton(_ list: ReminderListSnapshot) -> some View {
    Button {
      model.selectList(list.id)
    } label: {
      if list.id == model.activeListID {
        Label(list.title, systemImage: "checkmark")
      } else {
        Text(list.title)
      }
    }
    .disabled(list.source == .iCloud && model.authorization != .fullAccess)
  }

  @ViewBuilder
  private var reminderContent: some View {
    if model.lists.isEmpty {
      noListsContent
    } else if model.reminders.isEmpty {
      allDoneContent
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
        focusQuickAdd()
      }
    )
  }

  private var allDoneContent: some View {
    VStack(spacing: 10) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 30))
        .foregroundStyle(accentColor)
      Text("island.all-done").font(.headline)
      Text("all-done.detail")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Button(action: focusQuickAdd) {
        Label("quick-add.new", systemImage: "plus")
      }
      .buttonStyle(.borderedProminent)
      .tint(accentColor)
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(20)
  }

  private func focusQuickAdd() {
    if isPinned {
      quickAddFocused = true
    } else {
      focusQuickAddAfterPinning = true
      model.pinIsland()
    }
  }

  private var listCreationForm: some View {
    VStack(spacing: 14) {
      Label(L10n.text("list.new"), systemImage: "list.bullet.badge.plus")
        .font(.headline)

      TextField(L10n.text("list.name.placeholder"), text: $listNameDraft)
        .textFieldStyle(.roundedBorder)
        .focused($listNameFocused)
        .onSubmit { createListFromForm() }

      Picker(
        L10n.text("list.source"),
        selection: Binding(
          get: { model.requestedListCreationSource ?? .iCloud },
          set: { model.requestedListCreationSource = $0 }
        )
      ) {
        Label(L10n.text("source.icloud"), systemImage: "icloud").tag(ReminderSource.iCloud)
        Label(L10n.text("source.local"), systemImage: "desktopcomputer").tag(ReminderSource.local)
      }
      .pickerStyle(.segmented)

      if model.requestedListCreationSource == .iCloud, model.authorization != .fullAccess {
        Text("list.icloud-permission-required")
          .font(.caption)
          .foregroundStyle(.orange)
      }

      HStack {
        Button(L10n.text("common.cancel")) {
          model.cancelListCreation()
          listNameDraft = ""
        }
        Button(L10n.text("list.create")) { createListFromForm() }
          .keyboardShortcut(.defaultAction)
          .disabled(
            listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || (model.requestedListCreationSource == .iCloud
                && model.authorization != .fullAccess)
          )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var listRenameForm: some View {
    VStack(spacing: 14) {
      Label(L10n.text("list.rename"), systemImage: "pencil")
        .font(.headline)
      Text(listPendingRename?.title ?? "")
        .font(.caption)
        .foregroundStyle(.secondary)
      TextField(L10n.text("list.name.placeholder"), text: $listNameDraft)
        .textFieldStyle(.roundedBorder)
        .focused($listNameFocused)
        .onSubmit { renameListFromForm() }
      HStack {
        Button(L10n.text("common.cancel")) {
          listPendingRename = nil
          listNameDraft = ""
        }
        Button(L10n.text("common.save")) { renameListFromForm() }
          .keyboardShortcut(.defaultAction)
          .disabled(listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private func createListFromForm() {
    guard let source = model.requestedListCreationSource else { return }
    let title = listNameDraft
    Task {
      if await model.createList(title: title, source: source) {
        listNameDraft = ""
      }
    }
  }

  private func renameListFromForm() {
    guard let list = listPendingRename else { return }
    let title = listNameDraft
    Task {
      if await model.renameList(list, title: title) {
        listPendingRename = nil
        listNameDraft = ""
      }
    }
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

          if case .available = model.localStoreAvailability {
            Button {
              Task { await model.useLocal() }
            } label: {
              Label(L10n.text("source.use-local"), systemImage: "desktopcomputer")
            }
            .buttonStyle(.bordered)
          } else {
            HStack {
              Button("local-store.retry") {
                Task { await model.retryLocalStore() }
              }
              Button("local-store.show-in-finder") {
                model.showLocalDataInFinder()
              }
            }
          }
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
        VStack(spacing: 8) {
          HStack(spacing: 10) {
            Button("list.new-icloud") {
              model.requestNewList(source: .iCloud)
            }
            Button("source.use-local") {
              Task { await model.useLocal() }
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
          }
          HStack(spacing: 10) {
            Button("list.open-reminders") {
              SystemSettings.openReminders()
            }
            Button("list.check-again") {
              Task { await model.reload() }
            }
          }
        }
        .padding(.top, 4)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(20)
  }

  private var localEmptyContent: some View {
    VStack(spacing: 12) {
      Image(systemName: "desktopcomputer")
        .font(.system(size: 30))
        .foregroundStyle(accentColor)
      Text("list.no-local").font(.headline)
      Text("list.no-local.detail")
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      if isPinned {
        Button("list.new-local") {
          model.requestNewList(source: .local)
        }
        .buttonStyle(.borderedProminent)
        .tint(accentColor)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(20)
  }

  private var localStoreUnavailableContent: some View {
    VStack(spacing: 12) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .font(.system(size: 32))
        .foregroundStyle(.orange)
      Text("local-store.unavailable").font(.headline)
      if case let .unavailable(message, _) = model.localStoreAvailability {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      if isPinned {
        HStack {
          Button("local-store.retry") {
            Task { await model.retryLocalStore() }
          }
          .buttonStyle(.borderedProminent)
          Button("local-store.show-in-finder") {
            model.showLocalDataInFinder()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(24)
  }

  private var accentColor: Color {
    let accent = model.activeList?.accent ?? .fallback
    return Color(
      .sRGB, red: accent.red, green: accent.green, blue: accent.blue, opacity: accent.alpha)
  }

  @ViewBuilder
  private var sourceGlyph: some View {
    if let source = model.activeList?.source {
      Image(systemName: source.symbolName)
        .accessibilityHidden(true)
    }
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
      if model.editingReminderID != nil {
        model.cancelEditing()
      } else if model.requestedListCreationSource != nil {
        model.cancelListCreation()
      } else if listPendingRename != nil {
        listPendingRename = nil
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
