import SwiftUI
import ForgeCore

/// Settings: each learned pattern, its evidence, and what it changed.
struct AriaPersonalPatternsView: View {
    @ObservedObject private var store = AriaPersonalPatternStore.shared
    @State private var correctionID: String?
    @State private var correctionDraft = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            ForgeScreenStack(top: FDS.Spacing.sm) {
                Text("Patterns stay on this phone. They show up only after enough days and a clear signal. Confirm, correct, or let them expire.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()

                let visible = store.snapshot.visible
                if visible.isEmpty {
                    ForgeEmptyState(
                        icon: "waveform.path.ecg",
                        title: "No patterns yet",
                        message: "ARIA needs several nights, sessions, or calendar weeks before a pattern is real enough to show."
                    )
                } else {
                    ForEach(visible) { pattern in
                        patternCard(pattern)
                    }
                }

                let quiet = store.snapshot.patterns.filter { $0.status == .corrected || $0.status == .expired }
                if !quiet.isEmpty {
                    VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                        ForgeCardHeader("Paused")
                        ForEach(quiet) { pattern in
                            Text(pattern.title)
                                .font(HomeType.body)
                                .foregroundStyle(Color.textSecondary)
                                .forgeWrapping()
                        }
                    }
                    .forgeContentCard()
                }
            }
        }
        .forgeScreenBackground(accent: .ember)
        .navigationTitle("Your patterns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundColor(.ember)
            }
        }
        .sheet(isPresented: Binding(
            get: { correctionID != nil },
            set: { if !$0 { correctionID = nil } }
        )) {
            correctionSheet
                .transaction { $0.disablesAnimations = reduceMotion }
        }
    }

    private func patternCard(_ pattern: AriaPersonalPatternEngine.Pattern) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            ForgeCardHeader(
                pattern.status == .confirmed ? "Confirmed" : "Learned",
                meta: "\(Int((pattern.confidence * 100).rounded()))%"
            )
            Text(pattern.title)
                .font(HomeType.sessionTitle)
                .foregroundStyle(Color.textPrimary)
                .forgeWrapping()
            labeled("Evidence", pattern.evidence)
            labeled("What changed", pattern.changed)
            HStack(spacing: ForgeLayout.groupBreak) {
                ForgeTextLink(title: "Confirm", accent: .ember) {
                    store.applyConfirm(id: pattern.id)
                }
                ForgeTextLink(title: "Correct", accent: .steel) {
                    correctionID = pattern.id
                    correctionDraft = ""
                }
                ForgeTextLink(title: "Expire", accent: .danger) {
                    store.applyExpire(id: pattern.id)
                }
                Spacer(minLength: 0)
            }
        }
        .forgeContentCard()
        .accessibilityElement(children: .contain)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
            Text(title)
                .font(HomeType.micro)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
        }
    }

    private var correctionSheet: some View {
        NavigationStack {
            ScrollView {
                ForgeScreenStack(top: FDS.Spacing.lg) {
                    Text("Tell ARIA what this should have been. The pattern stops applying.")
                        .font(HomeType.body)
                        .foregroundStyle(Color.textSecondary)
                        .forgeWrapping()
                    TextField("Correction", text: $correctionDraft, axis: .vertical)
                        .font(HomeType.body)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(3...6)
                        .padding(FDS.Spacing.md)
                        .forgeInsetTile(radius: FDS.Radius.md)
                }
            }
            .forgeScreenBackground()
            .navigationTitle("Correct pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { correctionID = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let id = correctionID {
                            store.applyCorrect(id: id, note: correctionDraft)
                        }
                        correctionID = nil
                    }
                    .disabled(correctionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
