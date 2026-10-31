import Foundation
import Observation
import SwiftUI
import ForgeCore

/// First-run 4.2.3(ii) prompt: name the 210 MB size and ask before downloading.
enum AriaKokoroVoicePromptPolicy: Sendable {
    static let title = AriaKokoroDelivery.promptTitle
    static let body = AriaKokoroDelivery.promptBody
    static let downloadTitle = AriaKokoroDelivery.promptDownloadTitle
    static let laterTitle = AriaKokoroDelivery.promptLaterTitle

    static func shouldPresent(
        hasLocalModel: Bool,
        alreadyConsented: Bool,
        declined: Bool
    ) -> Bool {
        AriaKokoroDelivery.shouldAskToDownload(
            hasLocalModel: hasLocalModel,
            alreadyConsented: alreadyConsented,
            declined: declined
        )
    }
}

@MainActor
@Observable
final class AriaKokoroVoiceGate {
    static let shared = AriaKokoroVoiceGate()

    var showPrompt = false
    var isDownloading = false
    var statusLine: String?

    private init() {}

    func refresh(defaults: UserDefaults = .standard) async {
        await AriaKokoroModelStore.shared.discover()
        let hasModel = AriaKokoroModelStore.shared.hasVerifiedRuntime
        if hasModel {
            showPrompt = false
            _ = await AriaKokoroModelStore.shared.prefetchIfAllowed(defaults: defaults)
            return
        }
        let consented = defaults.bool(forKey: AriaKokoroDelivery.consentKey)
        let declined = defaults.bool(forKey: AriaKokoroDelivery.declinedKey)
        if consented {
            showPrompt = false
            isDownloading = true
            let ok = await AriaKokoroModelStore.shared.prefetchIfAllowed(defaults: defaults)
            isDownloading = false
            statusLine = ok ? nil : AriaKokoroVoice.loadFailedMessage
            return
        }
        showPrompt = AriaKokoroVoicePromptPolicy.shouldPresent(
            hasLocalModel: false,
            alreadyConsented: consented,
            declined: declined
        )
    }

    func acceptDownload(defaults: UserDefaults = .standard) async {
        defaults.set(true, forKey: AriaKokoroDelivery.consentKey)
        defaults.set(false, forKey: AriaKokoroDelivery.declinedKey)
        isDownloading = true
        statusLine = "Downloading 210 MB…"
        let ok = await AriaKokoroModelStore.shared.downloadPinnedBundle()
        isDownloading = false
        showPrompt = false
        statusLine = ok ? nil : AriaKokoroVoice.loadFailedMessage
    }

    func decline(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: AriaKokoroDelivery.declinedKey)
        showPrompt = false
    }
}

struct AriaKokoroVoiceSheet: View {
    @Bindable var gate: AriaKokoroVoiceGate

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: FDS.Spacing.lg) {
                Text(AriaKokoroVoicePromptPolicy.body)
                    .font(FDS.TypeScale.Dynamic.headline)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let statusLine = gate.statusLine {
                    Text(statusLine)
                        .font(FDS.TypeScale.Dynamic.body)
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                Button {
                    Task { await gate.acceptDownload() }
                } label: {
                    Text(gate.isDownloading ? "Downloading…" : AriaKokoroVoicePromptPolicy.downloadTitle)
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FDS.Spacing.lg)
                        .background(Color.ember, in: RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(gate.isDownloading)
                .accessibilityLabel("Download ARIA voice, 210 megabytes")

                Button {
                    gate.decline()
                } label: {
                    Text(AriaKokoroVoicePromptPolicy.laterTitle)
                        .font(FDS.TypeScale.Dynamic.caption)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, FDS.Spacing.md)
                }
                .buttonStyle(.plain)
                .disabled(gate.isDownloading)
            }
            .padding(FDS.Spacing.xl)
            .navigationTitle(AriaKokoroVoicePromptPolicy.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(gate.isDownloading)
    }
}
