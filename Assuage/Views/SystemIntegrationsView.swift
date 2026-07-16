import SwiftUI
import AppKit
import Contacts

/// The System Integrations tab: what the app adds to macOS, and a shortcut to
/// manage those extensions in System Settings. The Finder/Services/Quick Look rows
/// are read-only; Contacts is a live permission the app can request here.
struct SystemIntegrationsView: View {
    @Environment(PeopleLibrary.self) private var people

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Contacts", systemImage: "person.2")
                    Text("Read the public keys and forge links saved on your contacts, so you can encrypt to people by name and verify their signed notes. \(AppInfo.name) only adds keys when you ask, fetches a link only when you tell it to, and never deletes a contact.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 2)

                LabeledContent("Access", value: accessStatus)

                // The app can grant nothing itself once the choice is made — only the
                // first request happens in-app; turning access on or off afterwards is
                // System Settings' job.
                if people.authorization == .notDetermined {
                    Button("Allow Access to Contacts…") {
                        Task { await people.requestAccessAndLoad() }
                    }
                } else {
                    Button("Manage Access in System Settings…", action: openContactsPrivacySettings)
                }
            } header: {
                Text("Contacts")
            }

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
                Text("\(AppInfo.name) only reads what you hand it — no online services beyond the forge links you ask it to fetch. You control these in System Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Manage in System Settings…", action: openExtensionSettings)
            }
        }
        .formStyle(.grouped)
        .task { people.refreshAuthorization() }
    }

    /// A short, plain-language state for the Contacts permission.
    private var accessStatus: String {
        switch people.authorization {
        case .authorized: return String(localized: "On")
        case .notDetermined: return String(localized: "Not requested")
        case .denied: return String(localized: "Off")
        case .restricted: return String(localized: "Restricted")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private func openContactsPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Open System Settings ▸ Login Items & Extensions. The URL is undocumented and
    /// has shifted between releases, so treat the open as best-effort.
    private func openExtensionSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
