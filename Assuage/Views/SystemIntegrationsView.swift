import SwiftUI
import AppKit

/// The System Integrations tab: what the app adds to macOS, and a shortcut to
/// manage those extensions in System Settings. Read-only — the app can't toggle
/// them, and it reaches no network.
struct SystemIntegrationsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(SystemIntegration.all) { integration in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(integration.name, systemImage: integration.systemImage)
                        Text(integration.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("How \(AppInfo.name) integrates with your Mac")
            } footer: {
                Text("\(AppInfo.name) only reads what you hand it — no online services. You control these in System Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Manage in System Settings…", action: openExtensionSettings)
            }
        }
        .formStyle(.grouped)
    }

    /// Open System Settings ▸ Login Items & Extensions. The URL is undocumented and
    /// has shifted between releases, so treat the open as best-effort.
    private func openExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
