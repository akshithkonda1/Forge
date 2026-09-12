import Foundation
import SwiftUI
import ForgeCore

/// Weekly ARIA evaluation. The chat tab is for conversation; this is the
/// interview that actually collects standing context — energy, sleep, body,
/// next-week focus — and files it on-device plus `/ai/weekly-review`.
@MainActor
final class WeeklyAriaReviewStore: ObservableObject {
    static let shared = WeeklyAriaReviewStore()

    @Published var isDue = false
    @Published var showSheet = false
    @Published var isSubmitting = false
    @Published var lastSummary: String?
    @Published var answers: [String: String] = [:]

    let questions: [(id: String, prompt: String, hint: String)] = [
        ("energy", "How has your energy been this week?", "Low, mixed, or high — and what changed it."),
        ("sleep", "How did you actually sleep?", "Hours are optional. Quality and schedule matter more."),
        ("body", "Anything hurting, lingering, or off?", "Injuries, illness, cycle, stress. Empty is fine."),
        ("focus", "What should next week be about?", "Strength, recovery, consistency, or just showing up."),
        ("remember", "What should Forge remember about you?", "A preference, a constraint, a goal."),
        ("mood", "How has your mood actually been this week?", "Happy, flat, or Gollum-mode — this week, not your whole life."),
        ("social", "Did you want people around, or space?", "Seeing family vs hiding out both count."),
    ]

    static let openNotification = Notification.Name("forge.openWeeklyAria")

    private static let lastCompletedKey = "forge.aria.weekly.completed"
    private static let snoozedKey = "forge.aria.weekly.snoozed"
    private static let dueAfter: TimeInterval = 6 * 24 * 60 * 60

    private init() {
        refreshDue()
    }

    func refreshDue() {
        guard let last = UserDefaults.standard.object(forKey: Self.lastCompletedKey) as? Date else {
            isDue = true
            return
        }
        isDue = Date().timeIntervalSince(last) >= Self.dueAfter
    }

    func considerPresenting() {
        refreshDue()
        guard isDue, !isSnoozedToday() else { return }
        showSheet = true
    }

    func snoozeUntilTomorrow() {
        UserDefaults.standard.set(Date(), forKey: Self.snoozedKey)
        showSheet = false
    }

    private func isSnoozedToday() -> Bool {
        guard let snoozed = UserDefaults.standard.object(forKey: Self.snoozedKey) as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(snoozed)
    }

    func submit(store: AppStore) async {
        isSubmitting = true
        defer { isSubmitting = false }

        let cleaned = Dictionary(uniqueKeysWithValues: questions.map { q in
            (q.id, answers[q.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        })

        var facts: [String] = []
        if let energy = cleaned["energy"], !energy.isEmpty { facts.append("Weekly energy: \(energy)") }
        if let sleep = cleaned["sleep"], !sleep.isEmpty { facts.append("Weekly sleep: \(sleep)") }
        if let body = cleaned["body"], !body.isEmpty { facts.append("Body note: \(body)") }
        if let focus = cleaned["focus"], !focus.isEmpty { facts.append("Next-week focus: \(focus)") }
        if let remember = cleaned["remember"], !remember.isEmpty { facts.append(remember) }
        if let mood = cleaned["mood"], !mood.isEmpty { facts.append("Weekly mood: \(mood)") }
        if let social = cleaned["social"], !social.isEmpty { facts.append("Weekly social: \(social)") }

        let source = "weekly-checkin"
        for (kind, text) in cleaned where !text.isEmpty {
            AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "weekly_\(kind)",
                summary: text,
                source: source
            ))
        }
        if let mood = cleaned["mood"], let score = WeeklyMoodScale.score(from: mood) {
            AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "weekly_mood",
                summary: String(format: "%.0f", score),
                source: source
            ))
            AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                category: .inferences,
                kind: "weekly_mood_shift",
                summary: score <= 3
                    ? "This week is a withdrawal week — QoL mind weight should go gentle."
                    : "This week has lift — protect what's working.",
                source: source
            ))
        }

        let summary: String
        if facts.isEmpty {
            summary = "Weekly check-in logged. Nothing new to remember this time."
        } else {
            summary = "Weekly evaluation — " + facts.prefix(3).joined(separator: "; ") + "."
        }

        if let remote = await postReview(answers: cleaned) {
            lastSummary = remote.summary
            for fact in remote.facts { store.rememberDurable(fact) }
        } else {
            lastSummary = summary
            for fact in facts { store.rememberDurable(fact) }
        }

        UserDefaults.standard.set(Date(), forKey: Self.lastCompletedKey)
        isDue = false
        showSheet = false
        answers = [:]

        let opener = lastSummary.map {
            "I just finished this week's evaluation. \($0) Let's go deeper on whatever still needs a look."
        } ?? summary
        store.openChat(with: opener, voice: false)
    }

    private struct RemoteResult {
        let summary: String
        let facts: [String]
    }

    private func postReview(answers: [String: String]) async -> RemoteResult? {
        let url = AriaService.shared.baseURL.appendingPathComponent("ai/weekly-review")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["phase": "submit", "answers": answers]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, response) = try? await ForgeAPI.send(request),
              (200...299).contains(response.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let summary = json["summary"] as? String ?? ""
        let facts = json["facts"] as? [String] ?? []
        return RemoteResult(summary: summary, facts: facts)
    }
}

struct WeeklyAriaReviewSheet: View {
    @ObservedObject var review = WeeklyAriaReviewStore.shared
    @EnvironmentObject var store: AppStore
    private var lastHabit: DeepHabit? { AriaContextStore.shared.context.deepHabits.first }
    private var pendingHabit: TriedHabit? { HabitFeedbackStore.pendingFeedback() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Once a week ARIA sits down and actually asks — not a score, a conversation. Answers stay in your context on this device and, when the backend is up, on your account.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)

                    // Last habit breaker + outcome — closes the loop you asked for
                    if let habit = lastHabit {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: habit.category.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ember)
                                Text("Last habit: \(habit.title)").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.ember)
                            }
                            Text(habit.breaker).font(.system(size: 13)).foregroundStyle(Color.textPrimary)
                            Text(habit.evidence).font(.system(size: 11)).foregroundStyle(Color.textTertiary)
                            if let pending = pendingHabit, pending.habitId == habit.id {
                                Text("You tried this — did it work? Answer in Wellbeing → Today's Loop.")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.success)
                            } else if let tried = HabitFeedbackStore.tried().first(where: { $0.habitId == habit.id && $0.feedback != nil }) {
                                Text(tried.feedback == "yeah" ? "You said it worked ✓" : "You said it was too big — next breaker will be smaller")
                                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(tried.feedback == "yeah" ? Color.success : Color.warning)
                            }
                        }
                        .padding(12).background(Color.ember.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.ember.opacity(0.15), lineWidth: 1) }
                    }

                    ForEach(review.questions, id: \.id) { question in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.prompt)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text(question.hint)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textTertiary)
                            TextField("Your answer", text: Binding(
                                get: { review.answers[question.id] ?? "" },
                                set: { review.answers[question.id] = $0 }
                            ), axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(Color.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Button {
                        Task { await review.submit(store: store) }
                    } label: {
                        HStack {
                            if review.isSubmitting { ProgressView().tint(.white) }
                            Text(review.isSubmitting ? "Saving…" : "Save and talk with ARIA")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.ember)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(review.isSubmitting)
                }
                .padding(20)
            }
            .background(Color.background)
            .navigationTitle("Weekly evaluation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { review.snoozeUntilTomorrow() }
                }
            }
        }
    }
}
