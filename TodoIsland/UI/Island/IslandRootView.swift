import AppKit
import SwiftUI

enum ListCreationDraftPolicy {
  static func shouldResetName(
    previousSource: ReminderSource?,
    newSource: ReminderSource?
  ) -> Bool {
    previousSource == nil && newSource != nil
  }
}

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

      ZStack(alignment: .top) {
        if model.islandState == .collapsed {
          collapsedContent
            .transition(.opacity)
        } else {
          expandedContent
            .transition(
              .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
            )
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
      .animation(surfaceAnimation, value: model.islandState)
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
        if let candidate = model.listDeletionCandidate {
          Button(L10n.text("list.delete.confirm"), role: .destructive) {
            Task { await model.confirmListDeletion(candidate) }
          }
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
      .onChange(of: model.editingFocusRequestID) { _, _ in
        Task { @MainActor in editorTitleFocused = true }
      }
      .onChange(of: model.requestedListCreationSource) { previousSource, source in
        guard source != nil else { return }
        listPendingRename = nil
        if ListCreationDraftPolicy.shouldResetName(
          previousSource: previousSource,
          newSource: source
        ) {
          listNameDraft = ""
        }
        Task { @MainActor in listNameFocused = true }
      }
      .onChange(of: model.islandState) { _, state in
        if state == .collapsed {
          quickAddFocused = false
          editorTitleFocused = false
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
      HStack(alignment: .center, spacing: 0) {
        HStack(alignment: .center, spacing: 4) {
          sourceGlyph
            .frame(width: 18, height: 18, alignment: .center)
          Text(model.activeList?.title ?? L10n.text("list.none"))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(height: 18, alignment: .center)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .frame(height: 18, alignment: .center)
        .frame(width: collapsedSideContentWidth, alignment: .leading)
        .padding(.leading, collapsedOuterInset)

        Color.clear
          .frame(width: hostPhysicalNotchWidth)

        remainingCountRing
          .frame(width: collapsedSideContentWidth, alignment: .trailing)
          .padding(.trailing, collapsedOuterInset)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
      .accessibilityElement(children: .combine)
      .accessibilityLabel(collapsedAccessibilityLabel)
    } else {
      HStack(alignment: .center, spacing: 8) {
        sourceGlyph
          .frame(width: 18, height: 18, alignment: .center)
        Text(model.activeList?.title ?? L10n.text("list.none"))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(height: 18, alignment: .center)
        Spacer(minLength: 4)
        remainingCountRing
      }
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 14)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        Section(L10n.text("source.icloud")) {
          switch model.iCloudSourceMenuState {
          case .available:
            ForEach(model.iCloudLists) { list in
              listSelectionButton(list)
            }
          case .authorizationRequired:
            Button {
              restoreICloudAccess()
            } label: {
              Label(
                L10n.text(
                  model.authorization == .notDetermined
                    ? "permission.allow" : "permission.open-settings"),
                systemImage: "lock.open"
              )
            }
          case .empty:
            Button {
              model.requestNewList(source: .iCloud)
            } label: {
              Label(L10n.text("list.new-icloud"), systemImage: "plus")
            }
            Button {
              Task { await model.reload() }
            } label: {
              Label(L10n.text("list.check-again"), systemImage: "arrow.clockwise")
            }
            Button {
              SystemSettings.openReminders()
            } label: {
              Label(L10n.text("list.open-reminders"), systemImage: "list.bullet")
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
          if model.shouldShowAuthorizationLockInHeader {
            Image(systemName: "lock.fill")
              .font(.headline)
          } else if let activeList = model.activeList {
            Image(systemName: activeList.source.symbolName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if !model.shouldShowAuthorizationLockInHeader {
            Text(model.activeList?.title ?? L10n.text("list.none"))
              .font(.headline)
              .lineLimit(1)
          }
          if !model.shouldShowAuthorizationLockInHeader {
            Image(systemName: "chevron.down")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
      }
      .menuStyle(.borderlessButton)
      .accessibilityLabel(Text("list.switch"))

      Spacer()

      if model.isLoading {
        ProgressView().controlSize(.small)
      } else if model.canUseActiveList {
        Text("\(model.remainingCount)")
          .font(.system(size: 16, weight: .semibold, design: .monospaced))
          .foregroundStyle(accentColor)
          .accessibilityLabel(
            Text(String(format: L10n.text("reminders.remaining"), model.remainingCount)))
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

  private func restoreICloudAccess() {
    if model.authorization == .notDetermined {
      Task { await model.requestAccess() }
    } else {
      SystemSettings.openRemindersPrivacy()
    }
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
                .transition(.opacity.combined(with: .move(edge: .top)))
              if model.editingReminderID == reminder.id, let draft = model.draft {
                reminderEditor(draft)
                  .transition(.opacity.combined(with: .move(edge: .top)))
              }
            }
          }
          .padding(.vertical, 8)
          .animation(
            reduceMotion ? nil : .smooth(duration: 0.26, extraBounce: 0),
            value: model.reminders.map(\.id)
          )
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
    .animation(
      reduceMotion ? nil : .smooth(duration: 0.18, extraBounce: 0),
      value: model.selectedReminderID == reminder.id
    )
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
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 8) {
        ZStack {
          Circle().fill(accentColor.opacity(0.18))
          Image(systemName: "pencil")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(accentColor)
        }
        .frame(width: 28, height: 28)

        Text("editor.edit-reminder")
          .font(.subheadline.weight(.semibold))

        Spacer()
      }

      HStack(spacing: 9) {
        Image(systemName: "text.cursor")
          .font(.caption)
          .foregroundStyle(editorTitleFocused ? accentColor : .secondary)
        TextField(
          L10n.text("editor.title.placeholder"),
          text: Binding(
            get: { model.draft?.title ?? "" },
            set: { model.draft?.title = $0 }
          )
        )
        .textFieldStyle(.plain)
        .focused($editorTitleFocused)
        .onSubmit { model.saveEditing() }
      }
      .padding(.horizontal, 11)
      .frame(height: 38)
      .background {
        RoundedRectangle(cornerRadius: 10)
          .fill(.white.opacity(editorTitleFocused ? 0.09 : 0.06))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(
            editorTitleFocused ? accentColor.opacity(0.75) : .white.opacity(0.09),
            lineWidth: editorTitleFocused ? 1.25 : 1
          )
      }

      VStack(spacing: 8) {
        HStack(spacing: 10) {
          ZStack {
            RoundedRectangle(cornerRadius: 8)
              .fill(draft.hasDueDate ? accentColor.opacity(0.18) : .white.opacity(0.06))
            Image(systemName: "calendar")
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(draft.hasDueDate ? accentColor : .secondary)
          }
          .frame(width: 30, height: 30)

          Text("editor.due-date")
            .font(.subheadline.weight(.medium))

          Spacer()

          Toggle(
            "",
            isOn: Binding(
              get: { model.draft?.hasDueDate ?? false },
              set: { model.draft?.hasDueDate = $0 }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .tint(accentColor)
        }

        if draft.hasDueDate {
          Divider().overlay(.white.opacity(0.08))

          HStack(spacing: 10) {
            DatePicker(
              "",
              selection: Binding(
                get: { model.draft?.dueDate ?? Date() },
                set: { model.draft?.dueDate = $0 }
              ),
              displayedComponents: draft.includesTime
                ? [.date, .hourAndMinute] : [.date]
            )
            .labelsHidden()
            .controlSize(.small)

            Spacer()

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
          .transition(.opacity.combined(with: .move(edge: .top)))
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background {
        RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.04))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.08), lineWidth: 1)
      }
      .animation(
        reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0),
        value: draft.hasDueDate
      )

      HStack(spacing: 9) {
        Label(L10n.text("editor.priority"), systemImage: "flag")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        HStack(spacing: 6) {
          ForEach(
            [ReminderPriority.none, .low, .medium, .high],
            id: \.self
          ) { priority in
            priorityOption(priority, selectedPriority: draft.priority)
          }
        }
      }

      HStack(spacing: 9) {
        Spacer()
        Button(L10n.text("common.cancel")) { model.cancelEditing() }
          .buttonStyle(.bordered)
          .controlSize(.regular)

        Button(L10n.text("common.save")) { model.saveEditing() }
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
          .tint(accentColor)
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canSaveEditingDraft)
      }
    }
    .padding(13)
    .background {
      RoundedRectangle(cornerRadius: 14)
        .fill(.white.opacity(0.055))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(accentColor.opacity(0.24), lineWidth: 1)
    }
  }

  private func priorityOption(
    _ priority: ReminderPriority,
    selectedPriority: ReminderPriority
  ) -> some View {
    let isSelected = priority == selectedPriority
    let color = priority == .none ? accentColor : priorityColor(priority)
    let symbol = priority == .none ? "minus" : prioritySymbol(priority)

    return Button {
      model.draft?.priority = priority
    } label: {
      HStack(spacing: 4) {
        Image(systemName: symbol)
          .font(.system(size: 9, weight: .bold))
        priorityLabel(priority)
          .font(.caption.weight(.medium))
      }
      .foregroundStyle(isSelected ? color : .secondary)
      .frame(maxWidth: .infinity)
      .frame(height: 28)
      .background {
        RoundedRectangle(cornerRadius: 8)
          .fill(isSelected ? color.opacity(0.16) : .white.opacity(0.035))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(isSelected ? color.opacity(0.65) : .white.opacity(0.07), lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .animation(
      reduceMotion ? nil : .smooth(duration: 0.18, extraBounce: 0),
      value: isSelected
    )
  }

  private var quickAdd: some View {
    HStack(spacing: 8) {
      Image(systemName: "plus.circle.fill")
        .foregroundStyle(accentColor)
      TextField("quick-add.placeholder", text: $model.quickAddTitle)
        .textFieldStyle(.plain)
        .focused($quickAddFocused)
        .onSubmit { submitQuickAdd() }
        .accessibilityLabel(Text("quick-add.accessibility"))
      Button {
        submitQuickAdd()
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

  private func submitQuickAdd() {
    model.createQuickReminder()
    model.setQuickAddActive(false)
    quickAddFocused = false
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
    VStack(alignment: .leading, spacing: 13) {
      HStack(spacing: 11) {
        ZStack {
          Circle().fill(accentColor.opacity(0.18))
          Image(systemName: "list.bullet.badge.plus")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(accentColor)
        }
        .frame(width: 36, height: 36)

        VStack(alignment: .leading, spacing: 2) {
          Text("list.new")
            .font(.headline)
          Text("list.new.detail")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("list.name")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        HStack(spacing: 9) {
          Image(systemName: "text.cursor")
            .font(.caption)
            .foregroundStyle(listNameFocused ? accentColor : .secondary)
          TextField(L10n.text("list.name.placeholder"), text: $listNameDraft)
            .textFieldStyle(.plain)
            .focused($listNameFocused)
            .onSubmit { createListFromForm() }
        }
        .padding(.horizontal, 11)
        .frame(height: 39)
        .background {
          RoundedRectangle(cornerRadius: 11)
            .fill(.white.opacity(listNameFocused ? 0.09 : 0.065))
        }
        .overlay {
          RoundedRectangle(cornerRadius: 11)
            .stroke(
              listNameFocused ? accentColor.opacity(0.75) : .white.opacity(0.10),
              lineWidth: listNameFocused ? 1.25 : 1
            )
        }
      }

      VStack(alignment: .leading, spacing: 7) {
        Text("list.source")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          listSourceOption(.iCloud)
          listSourceOption(.local)
        }
      }

      if model.requestedListCreationSource == .iCloud, model.authorization != .fullAccess {
        Label("list.icloud-permission-required", systemImage: "exclamationmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      HStack(spacing: 10) {
        Spacer()
        Button(L10n.text("common.cancel")) {
          model.cancelListCreation()
          listNameDraft = ""
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Button(L10n.text("list.create")) { createListFromForm() }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .tint(accentColor)
          .keyboardShortcut(.defaultAction)
          .disabled(
            listNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              || (model.requestedListCreationSource == .iCloud
                && model.authorization != .fullAccess)
          )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 22)
    .padding(.vertical, 17)
  }

  private func listSourceOption(_ source: ReminderSource) -> some View {
    let isSelected = model.requestedListCreationSource == source
    let titleKey = source == .iCloud ? "source.icloud" : "source.local"
    let detailKey = source == .iCloud ? "source.icloud.detail" : "source.local.detail"

    return Button {
      model.requestedListCreationSource = source
    } label: {
      HStack(spacing: 9) {
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? accentColor.opacity(0.18) : .white.opacity(0.06))
          Image(systemName: source.symbolName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isSelected ? accentColor : .secondary)
        }
        .frame(width: 30, height: 30)

        VStack(alignment: .leading, spacing: 1) {
          Text(L10n.text(titleKey))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
          Text(L10n.text(detailKey))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer(minLength: 2)

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(isSelected ? accentColor : .white.opacity(0.18))
      }
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
      .background {
        RoundedRectangle(cornerRadius: 12)
          .fill(isSelected ? accentColor.opacity(0.10) : .white.opacity(0.035))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            isSelected ? accentColor.opacity(0.65) : .white.opacity(0.09),
            lineWidth: isSelected ? 1.25 : 1
          )
      }
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
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
      if model.islandState.showsAuthorizationActions {
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
    ZStack(alignment: .center) {
      Circle()
        .stroke(.green, lineWidth: 3)
      Text("\(model.remainingCount)")
        .font(.system(size: 9, weight: .black, design: .rounded))
        .foregroundStyle(.green)
        .monospacedDigit()
        .contentTransition(.numericText())
        .minimumScaleFactor(0.7)
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .frame(width: 18, height: 18)
    .offset(y: -3)
    .animation(
      reduceMotion ? nil : .smooth(duration: 0.22, extraBounce: 0),
      value: model.remainingCount
    )
  }

  private var surfaceAnimation: Animation? {
    guard !reduceMotion else { return nil }
    let motion = model.islandState.motionProfile
    let extraBounce = max(0, 1 - motion.dampingFraction) * 0.2
    return .smooth(duration: motion.response, extraBounce: extraBounce)
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
