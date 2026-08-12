import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject private var model: AppModel
  let finish: () -> Void

  var body: some View {
    VStack(spacing: 22) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 84, height: 84)
        .accessibilityHidden(true)

      VStack(spacing: 7) {
        Text("onboarding.title")
          .font(.largeTitle.bold())
        Text("onboarding.subtitle")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }

      permissionCard

      if model.authorization == .fullAccess {
        selectionCard
      }

      Spacer(minLength: 0)

      actionButton
    }
    .padding(28)
    .frame(width: 520, height: 520)
    .task { await model.start() }
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
  }

  private var permissionCard: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: permissionSymbol)
        .font(.title2)
        .foregroundStyle(permissionColor)
        .frame(width: 30)

      VStack(alignment: .leading, spacing: 6) {
        Text("onboarding.permission.title")
          .font(.headline)
        Text("onboarding.permission.detail")
          .font(.callout)
          .foregroundStyle(.secondary)
        Text("onboarding.privacy")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 14).fill(.secondary.opacity(0.08)))
  }

  private var selectionCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      Picker(
        L10n.text("onboarding.list"),
        selection: Binding(
          get: { model.activeListID ?? "" },
          set: { model.selectList($0) }
        )
      ) {
        if model.lists.isEmpty {
          Text("list.no-icloud").tag("")
        }
        ForEach(model.lists) { list in
          Text(list.title).tag(list.id)
        }
      }

      Picker(
        L10n.text("settings.display"),
        selection: Binding(
          get: { model.selectedDisplayID ?? "" },
          set: { model.selectedDisplayID = $0 }
        )
      ) {
        ForEach(model.displays) { display in
          Text(
            display.hasPhysicalNotch
              ? String(format: L10n.text("display.notched"), display.name)
              : display.name
          )
          .tag(display.id)
        }
      }
    }
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 14).fill(.secondary.opacity(0.08)))
  }

  @ViewBuilder
  private var actionButton: some View {
    switch model.authorization {
    case .notDetermined:
      Button {
        Task { await model.requestAccess() }
      } label: {
        Text("onboarding.allow")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    case .denied, .restricted:
      Button {
        SystemSettings.openRemindersPrivacy()
      } label: {
        Text("permission.open-settings")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    case .fullAccess:
      Button {
        model.completeOnboarding()
        finish()
      } label: {
        Text("onboarding.continue")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(model.activeListID == nil || model.selectedDisplayID == nil)
    }
  }

  private var permissionSymbol: String {
    switch model.authorization {
    case .fullAccess: "checkmark.shield.fill"
    case .denied, .restricted: "lock.trianglebadge.exclamationmark.fill"
    case .notDetermined: "hand.raised.fill"
    }
  }

  private var permissionColor: Color {
    switch model.authorization {
    case .fullAccess: .green
    case .denied, .restricted: .orange
    case .notDetermined: .accentColor
    }
  }
}
