import SwiftUI
import ForgeCore

/// You tab — foldered transparency for what ARIA knows.
struct WhatIKnowView: View {
    @ObservedObject private var aria = AriaContextStore.shared
    @State private var ledger = AriaKnowledgeLedgerStore.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Four folders. Same facts Life uses to grade QoL, and the same facts ARIA talks from.")
                    .font(.system(size: 14))
                    .foregroundColor(.textSecondary)

                if let snap = QualityOfLifeLivingStore.load() {
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
                        Text(QualityOfLifeBand(score: snap.overall).label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.ember)
                    }
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                ForEach(AriaKnowledgeCategory.allCases, id: \.self) { category in
                    folder(category)
                }
            }
            .padding(20)
        }
        .background(Color.background.ignoresSafeArea())
        .navigationTitle("What I Know?")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { ledger = AriaKnowledgeLedgerStore.load() }
        .onReceive(aria.objectWillChange) { _ in
            ledger = AriaKnowledgeLedgerStore.load()
        }
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
        .background(Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dateline(_ fact: AriaKnowledgeFact) -> String {
        let day = fact.createdAt.formatted(date: .abbreviated, time: .omitted)
        return "\(day) · \(fact.source) · \(fact.kind)"
    }
}
