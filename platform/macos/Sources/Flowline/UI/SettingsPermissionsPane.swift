import SwiftUI
import FlowlinePermissions

/// Permissions pane — thin wrapper so Settings sidebar owns every section.
public struct SettingsPermissionsPane: View {
    var manager: PermissionsManager

    public init(manager: PermissionsManager) {
        self.manager = manager
    }

    public var body: some View {
        Form {
            Section {
                PermissionsBannerView(manager: manager)
            } header: {
                Text("System Access")
            } footer: {
                Text("Screen Recording + Accessibility are required to capture workflows. Grant once for this exact app binary — rebuilding re-signs it and macOS drops the grant.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }
}
