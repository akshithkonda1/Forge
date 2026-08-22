import Foundation
import SwiftUI

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
        var summary: String
        var facts: [String]
    }

    private func postReview(answers: [String: String]) async -> RemoteResult? {
        let url = AriaService.shared.baseURL.appendingPathComponent("ai/weekly-review")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["phase": "submit", "answers": answers]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        guard let (data, response) = try? await ForgeAPI.send(request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Once a week ARIA sits down and actually asks — not a score, a conversation. Answers stay in your context on this device and, when the backend is up, on your account.")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)

                    ForEach(review.questions, id: \.id) { question in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.prompt)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.textPrimary)
                            Text(question.hint)
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                            TextField("Your answer", text: Binding(
                                get: { review.answers[question.id] ?? "" },
                                set: { review.answers[question.id] = $0 }
                            ), axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(Color.surfaceElevated)
                            .cornerRadius(12)
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
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.ember)
                        .cornerRadius(14)
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
