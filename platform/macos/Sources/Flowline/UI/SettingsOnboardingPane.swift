import SwiftUI

// MARK: - Settings → Onboarding (dev retrigger + defaults editor)
//
// Explicit home for the onboarding phase: replay the intro tour, edit the
// defaults new guides start from, or reset everything so the next launch
// replays first-run. Editing here writes `OnboardingDefaultsStore` only —
// existing guides keep their per-session style.

public struct SettingsOnboardingPane: View {
    var firstRun: FirstRunWindowController

    @State private var defaults: OnboardingDefaults = OnboardingDefaultsStore.load()
    @State private var showEditor = false
    @State private var tourState: String?

    public init(firstRun: FirstRunWindowController) {
        self.firstRun = firstRun
    }

    public var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Halo") {
                    Text("\(defaults.autoHalo ? "Auto · " : "")\(defaults.defaultHalo.label)")
                }
                LabeledContent("Keys") {
                    Text("\(defaults.keycapStyle.label) / \(defaults.mouseStyle.label)")
                }
                LabeledContent("Guide") {
                    Text("\(defaults.accent.label) · \(defaults.media.label) · \(defaults.numbering.label)")
                }
            } header: {
                Text("Current defaults")
            } footer: {
                Text("New guides start from these. Existing guides keep their own style.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("Replay intro tour") {
                    firstRun.show()
                    tourState = "Tour window opened."
                }
                Button("Edit onboarding defaults") { showEditor = true }
                Button("Reset onboarding state", role: .destructive) {
                    firstRun.resetForRelaunch()
                    defaults = OnboardingDefaultsStore.load()
                    tourState = "Cleared. Next launch replays first-run."
                }
                if let tourState {
                    Text(tourState).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Dev retrigger")
            } footer: {
                Text("Reset clears the tour flag and the defaults in one step.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showEditor) {
            OnboardingSetupView(
                defaults: defaults,
                onSave: { saved in
                    defaults = saved
                    showEditor = false
                }
            )
            .frame(minWidth: 560, minHeight: 620)
        }
        .onAppear { defaults = OnboardingDefaultsStore.load() }
    }

    private var statusText: String {
        FirstRunStore().hasCompleted ? "Completed" : "Not completed (tour will show)"
    }
}
