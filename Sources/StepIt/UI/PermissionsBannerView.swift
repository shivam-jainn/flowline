import SwiftUI
import StepItCore

public struct PermissionsBannerView: View {
    @State private var hasScreenRecording = PermissionsManager.shared.hasScreenRecordingPermission
    @State private var hasAccessibility = PermissionsManager.shared.hasAccessibilityPermission
    
    public init() {}
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 20))
                Text("macOS System Permissions")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    checkPermissions()
                }
                .buttonStyle(LinkButtonStyle())
            }
            
            Text("StepIt captures pinpoint screenshots, click coordinates, and target UI elements to automatically document workflows.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 10) {
                // Screen Recording Row
                HStack {
                    Image(systemName: hasScreenRecording ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasScreenRecording ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen Recording")
                            .font(.system(size: 13, weight: .semibold))
                        Text(hasScreenRecording ? "Permission granted." : "Required for high-res snapshots & micro-GIFs.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !hasScreenRecording {
                        Button("Open Settings") {
                            PermissionsManager.shared.openScreenRecordingSettings()
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Accessibility Row
                HStack {
                    Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasAccessibility ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.system(size: 13, weight: .semibold))
                        Text(hasAccessibility ? "Permission granted." : "Required to inspect buttons, labels & text fields.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if !hasAccessibility {
                        Button("Open Settings") {
                            PermissionsManager.shared.openAccessibilitySettings()
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            checkPermissions()
        }
    }
    
    private func checkPermissions() {
        hasScreenRecording = PermissionsManager.shared.hasScreenRecordingPermission
        hasAccessibility = PermissionsManager.shared.hasAccessibilityPermission
    }
}
