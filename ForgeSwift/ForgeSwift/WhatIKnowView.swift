import SwiftUI
import ForgeCore

/// You tab — foldered transparency for what ARIA knows.
struct WhatIKnowView: View {
    @ObservedObject private var aria = AriaContextStore.shared
    @State private var ledger = AriaKnowledgeLedgerStore.load()
    @State private var showLifestyleInterview = false
    @State private var persona = QualityOfLifeLivingStore.loadPersona()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Four folders. Same facts Life uses to grade QoL, and the same facts ARIA talks from.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)

                if let snap = QualityOfLifeLivingStore.load() {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Lifestyle QoL")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textTertiary)
                                Text("\(snap.overall)/100")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundColor(.textPrimary)
                            }
                            Spacer()
                            Text(snap.qualityBand.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(snap.qualityBand.color)
                        }
                        if !snap.drivers.isEmpty {
                            Text(snap.qualityBand == .thriving
                                 ? "Holding you up: \(snap.drivers.joined(separator: " · "))"
                                 : "Pulling: \(snap.drivers.joined(separator: " · "))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        if !snap.missingPillars.isEmpty {
                            Text("Still unmeasured: \(snap.missingPillars.joined(separator: ", "))")
                                .font(.system(size: 12))
                                .foregroundColor(.textMuted)
                        }
                        if !snap.coaching.isEmpty {
                            Text(snap.coaching)
                                .font(.system(size: 13))
                                .foregroundColor(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                    .forgeGlassCard(cornerRadius: 16, accent: .ember)
                }

                personaCard

                ForEach(AriaKnowledgeCategory.allCases, id: \.self) { category in
                    folder(category)
                }
            }
            .padding(20)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("What I Know?")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { refresh() }
        .onReceive(aria.objectWillChange) { _ in
            refresh()
        }
        .fullScreenCover(isPresented: $showLifestyleInterview) {
            LifestyleInterviewOverlay {
                showLifestyleInterview = false
                refresh()
            }
        }
    }

    private var personaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Who you are for QoL")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.textTertiary)
            Text(persona.archetype.title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            if let hours = persona.sleepNeedPreferenceHours {
                Text(String(format: "Sleep want: %.1f h", hours))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
            if let strain = persona.workStrain0to10 {
                Text(String(format: "Work strain: %.0f / 10", strain))
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
            }
            Button {
                QualityOfLifeLivingStore.clearInterviewCompleted()
                showLifestyleInterview = true
            } label: {
                Text(QualityOfLifeLivingStore.hasCompletedInterview()
                      ? "Update who I am"
                      : "Tell ARIA who you are")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func folder(_ category: AriaKnowledgeCategory) -> some View {
        let items = ledger.facts(in: category)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
                Text(category.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            if items.isEmpty {
                Text("Nothing in this folder yet.")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
            } else {
                ForEach(items.prefix(12)) { fact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fact.summary)
                            .font(.system(size: 13))
                            .foregroundColor(.textPrimary)
                        Text(dateline(fact))
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .forgeGlassCard(cornerRadius: 16, accent: .steel)
    }

    private func dateline(_ fact: AriaKnowledgeFact) -> String {
        let day = fact.createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(day) · \(fact.source) · \(fact.kind)"
    }

    private func refresh() {
        ledger = AriaKnowledgeLedgerStore.load()
        persona = QualityOfLifeLivingStore.loadPersona()
    }
}
