import SwiftUI
import FlowlinePublishing

// MARK: - Onboarding setup phase (explicit defaults picker)
//
// Second half of first-run: after the keyframe tour, the user picks the
// visuals every new guide starts from. Same pickers as the editor style
// panel, but writing to `OnboardingDefaults` (global defaults) instead of
// a per-session `FlowGuideStyle`. Tokens only; live preview at the top.

public struct OnboardingSetupView: View {
    @State var defaults: OnboardingDefaults
    var onSave: (OnboardingDefaults) -> Void = { _ in }
    var onBack: (() -> Void)? = nil

    @Environment(\.colorScheme) private var scheme

    public init(
        defaults: OnboardingDefaults = OnboardingDefaultsStore.load(),
        onSave: @escaping (OnboardingDefaults) -> Void = { _ in },
        onBack: (() -> Void)? = nil
    ) {
        _defaults = State(initialValue: defaults)
        self.onSave = onSave
        self.onBack = onBack
    }

    public var body: some View {
        let t = FlowComponent.for(scheme)
        VStack(spacing: 0) {
            preview
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Form {
                Section {
                    Toggle("Auto Halo — mark interactions automatically", isOn: $defaults.autoHalo)
                        .font(.system(size: 12))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96))], spacing: 8) {
                        ForEach(FlowlineHaloKind.allCases, id: \.self) { kind in
                            Button(action: { withAnimation(FlowMotion.standardFast) { defaults.defaultHalo = kind } }) {
                                VStack(spacing: 4) {
                                    Image(systemName: kind.systemImage)
                                        .font(.system(size: 15))
                                    Text(kind.label)
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(defaults.defaultHalo == kind ? FlowSemantic.for(scheme).accentDefault : t.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .background(defaults.defaultHalo == kind ? FlowSemantic.for(scheme).accentSubtle : t.surfaceSubtle)
                                .cornerRadius(FlowComponent.radiusSM)
                            }
                            .buttonStyle(FlowPressStyle())
                            .help(kind.label)
                        }
                    }
                } header: {
                    Text("Default halo")
                } footer: {
                    Text("Used when Auto Halo places marks, and as the starting pick in the halo panel.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    ForEach(KeycapStyle.allCases, id: \.self) { ks in
                        Button(action: { withAnimation(FlowMotion.standardFast) { defaults.keycapStyle = ks } }) {
                            HStack(spacing: 10) {
                                KeyStyleThumbnail(ks)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ks.label).font(.system(size: 12, weight: defaults.keycapStyle == ks ? .semibold : .regular))
                                    Text(ks.blurb).font(.system(size: 11)).foregroundColor(t.textSecondary)
                                }
                                Spacer()
                                if defaults.keycapStyle == ks {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(defaults.keycapStyle == ks ? FlowSemantic.for(scheme).accentSubtle : t.surfaceSubtle)
                            .cornerRadius(FlowComponent.radiusSM)
                        }
                        .buttonStyle(FlowPressStyle())
                    }
                } header: {
                    Text("Keycap style")
                }

                Section {
                    ForEach(MouseStyle.allCases, id: \.self) { ms in
                        Button(action: { withAnimation(FlowMotion.standardFast) { defaults.mouseStyle = ms } }) {
                            HStack(spacing: 10) {
                                MouseStyleThumbnail(ms)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(ms.label).font(.system(size: 12, weight: defaults.mouseStyle == ms ? .semibold : .regular))
                                    Text(ms.blurb).font(.system(size: 11)).foregroundColor(t.textSecondary)
                                }
                                Spacer()
                                if defaults.mouseStyle == ms {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(FlowSemantic.for(scheme).accentDefault)
                                }
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(defaults.mouseStyle == ms ? FlowSemantic.for(scheme).accentSubtle : t.surfaceSubtle)
                            .cornerRadius(FlowComponent.radiusSM)
                        }
                        .buttonStyle(FlowPressStyle())
                    }
                } header: {
                    Text("Mouse style")
                }

                Section {
                    HStack(spacing: 8) {
                        ForEach(FlowAccentChoice.allCases, id: \.self) { choice in
                            Button(action: { withAnimation(FlowMotion.standardFast) { defaults.accent = choice } }) {
                                Circle()
                                    .fill(choice.color(for: scheme))
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().stroke(t.textInverse, lineWidth: defaults.accent == choice ? 2 : 0))
                                    .scaleEffect(defaults.accent == choice ? 1.12 : 1.0)
                            }
                            .buttonStyle(FlowPressStyle())
                            .help(choice.label)
                        }
                    }
                    .padding(.vertical, 2)
                    Picker("Screenshots", selection: $defaults.media) {
                        ForEach(FlowMediaTreatment.allCases, id: \.self) { m in Text(m.label).tag(m) }
                    }
                    Picker("Numbering", selection: $defaults.numbering) {
                        ForEach(FlowNumbering.allCases, id: \.self) { n in Text(n.label).tag(n) }
                    }
                } header: {
                    Text("Guide look")
                } footer: {
                    Text("New guides start from these. Existing guides keep their own style.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(maxHeight: .infinity)

            footer
        }
    }

    // Live sample driven by the current picks.
    private var preview: some View {
        let t = FlowComponent.for(scheme)
        let sem = FlowSemantic.for(scheme)
        return HStack(spacing: 12) {
            KeyComboCaps("⌘⇧K", style: defaults.keycapStyle)
            MouseClickHalo(style: defaults.mouseStyle)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(t.textTertiary)
                Text("\(defaults.defaultHalo.label) · \(defaults.keycapStyle.label) · \(defaults.mouseStyle.label)")
                    .font(.system(size: 12))
                    .foregroundColor(t.textPrimary)
            }
            Spacer()
            Circle()
                .fill(defaults.accent.color(for: scheme))
                .frame(width: 16, height: 16)
                .overlay(Circle().stroke(sem.accentSubtle, lineWidth: 3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(t.surface)
        .cornerRadius(FlowComponent.radiusMD)
        .overlay(RoundedRectangle(cornerRadius: FlowComponent.radiusMD).stroke(t.border, lineWidth: 1))
    }

    private var footer: some View {
        let t = FlowComponent.for(scheme)
        return HStack(spacing: 12) {
            if let onBack {
                Button("Back") { onBack() }
                    .buttonStyle(FlowPressStyle())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(t.textSecondary)
            }
            Spacer()
            Button("Save defaults") {
                OnboardingDefaultsStore.save(defaults)
                onSave(defaults)
            }
            .buttonStyle(FlowPressStyle())
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(t.primaryFg)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(t.primaryBg)
            .cornerRadius(FlowComponent.radiusSM)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}
