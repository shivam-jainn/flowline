import SwiftUI
import AppKit
import StepItPermissions
import StepItStorage
import StepItMacCapture
import StepItCaptureAPI
import StepItPublishing
import StepItAIGateway
import StepItPipeline
import StepItEngine
import StepItIR

public struct PermissionsBannerView: View {
    private let manager: PermissionsManager
    private let onContinue: (() -> Void)?
    @State private var hasScreenRecording: Bool
    @State private var hasAccessibility: Bool

    public init(manager: PermissionsManager = PermissionsManager(), onContinue: (() -> Void)? = nil) {
        self.manager = manager
        self.onContinue = onContinue
        self._hasScreenRecording = State(initialValue: manager.hasScreenRecordingPermission)
        self._hasAccessibility = State(initialValue: manager.hasAccessibilityPermission)
    }
    
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
                            manager.openScreenRecordingSettings()
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // macOS applies Screen Recording only to a fresh launch:
                // granting in Settings then hitting Refresh can never turn
                // green until the app is quit and reopened.
                if !hasScreenRecording {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.orange)
                        Text("After granting, quit and reopen StepIt — Refresh alone can't pick it up.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Quit & Reopen") {
                            relaunchApp()
                        }
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
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
                            manager.openAccessibilitySettings()
                        }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // All granted: this used to be a dead end (two ticks, no action).
            // Offer the onward step explicitly.
            if hasScreenRecording && hasAccessibility {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("You're all set — StepIt can capture and observe.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Start Recording") {
                        onContinue?()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.small)
                    .disabled(onContinue == nil)
                }
                .padding(10)
                .background(Color.green.opacity(0.08))
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
        hasScreenRecording = manager.hasScreenRecordingPermission
        hasAccessibility = manager.hasAccessibilityPermission
        // Observable verdicts: GUI-vs-CLI permission mismatches are otherwise
        // undebuggable (unified log: `log show --predicate 'process == "StepIt"'`).
        NSLog("StepIt perms verdict: screen=%@ ax=%@", hasScreenRecording as NSNumber, hasAccessibility as NSNumber)
        Self.appendDiagnosticsLine("check screen=\(hasScreenRecording) ax=\(hasAccessibility)")
    }

    /// File fallback for verdicts (unified log swallows NSLog from some launch
    /// contexts): `/tmp/stepit-perms.log`, one line per check.
    static func appendDiagnosticsLine(_ message: String) {
        let line = "\(Date()) pid=\(ProcessInfo.processInfo.processIdentifier) \(message) bundle=\(Bundle.main.bundleURL.path)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = URL(fileURLWithPath: "/tmp/stepit-perms.log")
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }

    /// Relaunches the app so granted Screen Recording takes effect (macOS
    /// only applies it to a fresh launch). `NSApp.terminate` alone just quits;
    /// this opens our own bundle first, then quits — and falls back to
    /// terminate when not running from a bundle (e.g. `swift run`).
    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let isBundled = bundleURL.pathExtension == "app"
            && FileManager.default.fileExists(atPath: bundleURL.path)
        if isBundled {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [bundleURL.path]
            try? process.run()
        }
        NSApplication.shared.terminate(nil)
    }
}
