import SwiftUI

struct SleepStreakDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let streak: Int

    private let milestones: [(days: Int, title: String, icon: String)] = [
        (7,   "A week of nights",  "checkmark"),
        (30,  "A month of nights", "moon.stars.fill"),
        (100, "A hundred nights",  "moon.fill"),
        (365, "A year of nights",  "calendar"),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Hero
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [Color.ember, Color.ember.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 100, height: 100)
                                    .shadow(color: Color.ember.opacity(0.45), radius: 20, y: 8)
                                Image(systemName: "moon.fill").font(.system(size: 46)).foregroundColor(.white)
                            }
                            Text("\(streak) nights").font(.system(size: 36, weight: .black, design: .rounded)).foregroundColor(.textPrimary)
                            Text("Nights logged, in a row").font(.system(size: 16)).foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 28)

                        // Milestones
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Logged nights").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach(milestones, id: \.days) { m in
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(streak >= m.days ? Color.ember.opacity(0.15) : Color.surfaceElevated).frame(width: 42, height: 42)
                                            Image(systemName: streak >= m.days ? "checkmark" : m.icon)
                                                .font(.system(size: 16)).foregroundColor(streak >= m.days ? .ember : .textMuted)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(m.title).font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                                            Text("\(m.days) days").font(.system(size: 12)).foregroundColor(.textSecondary)
                                        }
                                        Spacer()
                                        if streak < m.days {
                                            Text("\(m.days - streak) to go")
                                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.steel)
                                                .padding(.horizontal, 10).padding(.vertical, 5)
                                                .background(Color.steel.opacity(0.1)).cornerRadius(8)
                                        }
                                    }
                                    .padding(14).background(Color.surface).cornerRadius(14)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(streak >= m.days ? Color.ember.opacity(0.3) : Color.borderColor.opacity(0.4), lineWidth: 1))
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)

                        // Benefits
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Why nights in a row matter").font(.system(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach([("heart.fill", "Improved cardiovascular health"), ("brain.head.profile", "Enhanced cognitive function"), ("figure.run", "Better athletic performance"), ("face.smiling.fill", "Elevated mood & energy")], id: \.0) { icon, text in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon).font(.system(size: 14)).foregroundColor(.steel).frame(width: 20)
                                        Text(text).font(.system(size: 13)).foregroundColor(.textPrimary)
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.surfaceElevated).cornerRadius(12)
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold)
                }
            }
        }
    }
}

struct AISleepChatView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    private struct Turn: Identifiable {
        let id = UUID()
        let isUser: Bool
        let text: String
    }

    @State private var input = ""
    @State private var turns: [Turn] = []
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                if turns.isEmpty {
                                    Text("Ask me anything about your sleep patterns, recovery, or how to optimize your rest for better performance.")
                                        .font(.system(size: 14)).foregroundColor(.textSecondary)
                                        .multilineTextAlignment(.center).lineSpacing(5)
                                        .frame(maxWidth: .infinity)
                                        .padding(.horizontal, 24).padding(.top, 16)
                                }
                                ForEach(turns) { turn in
                                    HStack {
                                        if turn.isUser { Spacer(minLength: 40) }
                                        Text(turn.text)
                                            .font(.system(size: 14))
                                            .foregroundColor(turn.isUser ? .white : .textPrimary)
                                            .padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(turn.isUser ? Color.steel : Color.surface)
                                            .cornerRadius(16)
                                        if !turn.isUser { Spacer(minLength: 40) }
                                    }
                                    .id(turn.id)
                                }
                                if isSending {
                                    HStack {
                                        ProgressView().tint(.steel)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }
                            .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                        .onChange(of: turns.count) { _, _ in
                            guard let last = turns.last else { return }
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        TextField("Ask about your sleep…", text: $input)
                            .font(.system(size: 15)).foregroundColor(.textPrimary).tint(.steel)
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            .background(Color.surfaceElevated).cornerRadius(14)
                            .onSubmit(send)
                        Button(action: send) {
                            Circle().fill(Color.steel).frame(width: 44, height: 44)
                                .overlay(Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                                .shadow(color: Color.steel.opacity(0.35), radius: 8, y: 3)
                        }
                        .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? 0.4 : 1)
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 20)
                }
            }
            .navigationTitle("Sleep AI — ARIA")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.steel).fontWeight(.semibold)
                }
            }
        }
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        turns.append(Turn(isUser: true, text: text))
        isSending = true
        Task {
            let response = await store.ariaInsight(prompt: text, agent: .sleep)
            let reply = response?.proseSummary ?? response?.message
                ?? "I couldn't reach a sleep read just now — try again in a moment."
            turns.append(Turn(isUser: false, text: reply))
            AriaContextStore.shared.addInsight("Sleep chat: asked \"\(text)\" — \(reply)")
            isSending = false
        }
    }
}

struct AISleepPredictionDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tonight's Recommendation").font(.system(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("10:15 PM").font(.system(size: 40, weight: .black, design: .rounded)).foregroundColor(.steel)
                                Text("bedtime").font(.system(size: 16)).foregroundColor(.textSecondary)
                            }
                            Text("Wake at 6:15 AM for 8 hours of sleep").font(.system(size: 14)).foregroundColor(.textSecondary)
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Why This Time?").font(.system(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                            VStack(spacing: 10) {
                                ForEach([("figure.strengthtraining.traditional", "Heavy workout tomorrow — need optimal recovery"),
                                         ("chart.line.uptrend.xyaxis", "Your 90-min sleep cycles align best with 10 PM"),
                                         ("heart.fill", "HRV trends show earlier sleep improves your recovery by 18%")], id: \.0) { icon, text in
                                    HStack(spacing: 12) {
                                        Image(systemName: icon).font(.system(size: 14)).foregroundColor(.steel).frame(width: 20)
                                        Text(text).font(.system(size: 13)).foregroundColor(.textPrimary)
                                    }
                                    .padding(14).background(Color.surfaceElevated).cornerRadius(12)
                                }
                            }
                        }
                        .padding(20).background(Color.surface).cornerRadius(20)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Prediction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundColor(.steel).fontWeight(.semibold)
                }
            }
        }
    }
}

struct SleepPersonalizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var hkService: HealthKitSleepService
    @EnvironmentObject var store: AppStore
    @State private var draft = UserSleepProfile()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Your chronotype shapes scoring, goals, sunrise, and smart wake.")
                            .font(.system(size: 14))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(4)

                        VStack(spacing: 10) {
                            ForEach(Chronotype.allCases) { type in
                                Button {
                                    draft.chronotype = type
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: type.icon)
                                            .font(.system(size: 18))
                                            .foregroundColor(draft.chronotype == type ? .white : .steel)
                                            .frame(width: 40, height: 40)
                                            .background(draft.chronotype == type ? Color.steel : Color.surfaceElevated)
                                            .cornerRadius(12)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(type.displayName)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(.textPrimary)
                                            Text(type.tagline)
                                                .font(.system(size: 12))
                                                .foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        if draft.chronotype == type {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.steel)
                                        }
                                    }
                                    .padding(14)
                                    .background(Color.surface)
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(draft.chronotype == type ? Color.steel.opacity(0.5) : Color.borderColor.opacity(0.4), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Coaching personality")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextField("e.g. direct, encouraging, data-focused", text: $draft.personality)
                                .padding(12)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lifestyle notes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                            TextEditor(text: $draft.notes)
                                .frame(minHeight: 90)
                                .padding(8)
                                .background(Color.surfaceElevated)
                                .cornerRadius(12)
                                .scrollContentBackground(.hidden)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Sleep Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { draft = hkService.userProfile }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hkService.updateProfile(draft)
                        if !store.sleepData.isEmpty {
                            Task {
                                let rescored = await hkService.fetchRecentSleepData(days: 14)
                                store.mergeSleepDataLocally(rescored)
                            }
                        }
                        dismiss()
                    }
                    .foregroundColor(.steel)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (i, sv) in subviews.enumerated() {
            sv.place(at: CGPoint(x: bounds.minX + result.positions[i].x, y: bounds.minY + result.positions[i].y), proposal: .unspecified)
        }
    }
    struct FlowResult {
        var size: CGSize = .zero; var positions: [CGPoint] = []
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0; var y: CGFloat = 0; var lineH: CGFloat = 0
            for sv in subviews {
                let sz = sv.sizeThatFits(.unspecified)
                if x + sz.width > maxWidth && x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
                positions.append(CGPoint(x: x, y: y))
                lineH = max(lineH, sz.height); x += sz.width + spacing
            }
            size = CGSize(width: maxWidth, height: y + lineH)
        }
    }
}
