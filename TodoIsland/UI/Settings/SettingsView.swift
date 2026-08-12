import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var model: AppModel
  @ObservedObject private var launchAtLogin = LaunchAtLoginService.shared

  var body: some View {
    Form {
      Section("settings.reminders") {
        LabeledContent("settings.permission") {
          Text(permissionLabel)
            .foregroundStyle(permissionColor)
        }

        if model.authorization != .fullAccess {
          Button("permission.open-settings") {
            SystemSettings.openRemindersPrivacy()
          }
        }
      }

      Section("settings.island") {
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

        LabeledContent("settings.fullscreen") {
          Text("settings.fullscreen.policy")
            .foregroundStyle(.secondary)
        }

        Toggle(
          L10n.text("settings.launch-at-login"),
          isOn: Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
          )
        )
      }

      Section("settings.about") {
        LabeledContent("app.name", value: "1.0")
        Text("settings.privacy")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button("menu.quit", role: .destructive) { NSApp.terminate(nil) }
      }
    }
    .formStyle(.grouped)
    .padding(16)
    .frame(width: 520, height: 410)
    .task {
      model.reloadDisplays()
      launchAtLogin.refresh()
    }
    .alert(
      L10n.text("error.title"),
      isPresented: Binding(
        get: { launchAtLogin.lastError != nil },
        set: { if !$0 { launchAtLogin.lastError = nil } }
      )
    ) {
      Button(L10n.text("common.ok")) { launchAtLogin.lastError = nil }
    } message: {
      Text(launchAtLogin.lastError ?? "")
    }
  }

  private var permissionLabel: LocalizedStringKey {
    switch model.authorization {
    case .fullAccess: "permission.full-access"
    case .notDetermined: "permission.not-determined"
    case .denied: "permission.denied"
    case .restricted: "permission.restricted"
    }
  }

  private var permissionColor: Color {
    model.authorization == .fullAccess ? .green : .orange
  }
}
