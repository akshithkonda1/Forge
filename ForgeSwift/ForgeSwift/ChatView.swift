import SwiftUI

// MARK: - Quick actions (mirrors QUICK_ACTIONS in chat-page.tsx)

private let quickActions = [
    "How should I train today?",
    "I'm not feeling it",
    "Explain my sleep data",
    "Adjust my plan",
    "I have an injury/pain",
]

private let coachingMessages = [
    "Slow down the eccentric — 3 seconds on the way down",
    "Heart rate is elevated. Take an extra 30 seconds rest",
    "Last set was easy. Let's bump up 5lbs",
    "You're crushing it. Two more reps.",
    "Keep your core braced. Tight through the whole rep.",
    "Control the weight — don't let it control you",
    "Good form. Maintain that bar path.",
    "Breathe out on the exertion. Stay in rhythm.",
]

// MARK: - Chat Page (mirrors chat-page.tsx)

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var scrollProxy: ScrollViewProxy? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ChatHeaderView()

            // Messages
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(store.chatMessages) { msg in
                            MessageBubbleView(message: msg)
                                .id(msg.id)
                        }
                        if isTyping {
                            TypingIndicatorView()
                                .id("typing")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: store.chatMessages.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onChange(of: isTyping) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .background(Color.background)

            // Input area
            ChatInputAreaView(inputText: $inputText, isTyping: $isTyping)
        }
        .background(Color.background.ignoresSafeArea())
    }
}

// MARK: - Header

struct ChatHeaderView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            // AI Avatar
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(Color.ember.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16))
                        .foregroundColor(.ember)
                }
                // Online dot
                ZStack {
                    Circle().fill(Color.background).frame(width: 12, height: 12)
                    Circle().fill(Color.success).frame(width: 10, height: 10)
                    Circle().fill(Color.success).frame(width: 6, height: 6)
                        .scaleEffect(pulse ? 1.4 : 1)
                        .opacity(pulse ? 0.6 : 1)
                        .animation(.easeInOut(duration: 1.2).repeatForever(), value: pulse)
                }
                .offset(x: 2, y: 2)
            }
            .onAppear { pulse = true }

            VStack(alignment: .leading, spacing: 2) {
                Text("Forge AI")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 5) {
                    Circle().fill(Color.ember).frame(width: 6, height: 6)
                    Text("Online").font(.system(size: 12)).foregroundColor(.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Color.background.opacity(0.85)
                .background(.ultraThinMaterial.opacity(0.5))
        )
        .overlay(Rectangle().fill(Color.borderColor).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Message Bubble (mirrors MessageBubble in chat-page.tsx)

struct MessageBubbleView: View {
    let message: ChatMessage

    var isTrainer: Bool { message.role == .trainer }

    var body: some View {
        HStack {
            if !isTrainer { Spacer(minLength: 48) }

            VStack(alignment: isTrainer ? .leading : .trailing, spacing: 4) {
                // Text bubble
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(isTrainer ? Color.surfaceElevated : Color.ember.opacity(0.9))
                    .cornerRadius(isTrainer ? 18 : 18)
                    .cornerRadius(isTrainer ? 4 : 18, corners: isTrainer ? .bottomLeft : .bottomRight)

                // Rich card
                if let card = message.richCard {
                    RichCardView(card: card)
                        .padding(.top, 6)
                }

                // Timestamp
                Text(formatTime(message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 4)
            }

            if isTrainer { Spacer(minLength: 48) }
        }
    }

    func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }
}

// Rounded corners helper
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Rich Cards

struct RichCardView: View {
    let card: RichCardData

    var body: some View {
        switch card.type {
        case .workoutPlan:
            WorkoutRichCardView(card: card)
        case .dataChart:
            DataChartRichCardView(card: card)
        }
    }
}

struct WorkoutRichCardView: View {
    let card: RichCardData
    @State private var expanded = false
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.workoutName ?? "Workout Plan")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 10) {
                        Label("\(card.workoutDuration ?? 0) min", systemImage: "clock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                        Label("\(card.workoutExercises?.count ?? 0) exercises", systemImage: "list.bullet")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                }
                Spacer()
                Button(action: { withAnimation(.spring(response: 0.3)) { expanded.toggle() } }) {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
            .padding(14)

            // Exercise list (expanded)
            if expanded, let exercises = card.workoutExercises {
                Divider().background(Color.borderColor)
                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack {
                            Text("\(idx+1).")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.textMuted)
                                .frame(width: 20, alignment: .leading)
                            Text(ex.name)
                                .font(.system(size: 13))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(ex.sets)×\(ex.reps)")
                                .font(.system(size: 11))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        if idx < exercises.count - 1 {
                            Divider().background(Color.borderColor).padding(.leading, 14)
                        }
                    }
                }
            }

            Divider().background(Color.borderColor)

            // Start button
            Button(action: { store.startWorkout(); store.activeTab = .workout }) {
                Text("Start This Workout")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ember)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
    }
}

struct DataChartRichCardView: View {
    let card: RichCardData
    @State private var appear = false

    var values: [Double] { card.chartValues ?? [] }
    var maxVal: Double { values.max() ?? 1 }
    var minVal: Double { values.min() ?? 0 }
    var chartColor: Color { card.chartColor ?? .steel }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.chartTitle ?? "Trend")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 14)

            // Mini bar/sparkline chart
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { idx, val in
                    let normalised = maxVal > minVal ? (val - minVal) / (maxVal - minVal) : 1
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chartColor.opacity(0.3 + 0.7 * normalised))
                        .frame(maxWidth: .infinity)
                        .frame(height: appear ? max(6, 40 * CGFloat(normalised)) : 4)
                        .animation(.easeOut(duration: 0.5).delay(Double(idx) * 0.05), value: appear)
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 14)

            if let insight = card.chartInsight {
                Text(insight)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(2)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))
        .onAppear { withAnimation { appear = true } }
    }
}

// MARK: - Typing Indicator (mirrors TypingIndicator in chat-page.tsx)

struct TypingIndicatorView: View {
    @State private var animate = false

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.textTertiary)
                        .frame(width: 6, height: 6)
                        .opacity(animate ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.2),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.surfaceElevated)
            .cornerRadius(18)
            .cornerRadius(4, corners: .bottomLeft)

            Spacer()
        }
        .onAppear { animate = true }
    }
}

// MARK: - Chat Input Area

struct ChatInputAreaView: View {
    @EnvironmentObject var store: AppStore
    @Binding var inputText: String
    @Binding var isTyping: Bool
    @FocusState private var focused: Bool

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTyping else { return }

        let userMsg = ChatMessage(id: "user-\(Date().timeIntervalSince1970)",
                                  role: .user, content: trimmed, timestamp: Date())
        store.addMessage(userMsg)
        inputText = ""
        isTyping = true

        let delay = 1.2 + Double.random(in: 0...0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let (content, richCard) = store.trainerResponse(for: trimmed)
            let trainerMsg = ChatMessage(id: "trainer-\(Date().timeIntervalSince1970)",
                                          role: .trainer, content: content,
                                          timestamp: Date(), richCard: richCard)
            store.addMessage(trainerMsg)
            isTyping = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Separator
            Rectangle().fill(Color.borderColor).frame(height: 1)

            // Quick actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickActions, id: \.self) { action in
                        Button(action: { sendMessage(action) }) {
                            Text(action)
                                .font(.system(size: 12))
                                .foregroundColor(.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.clear)
                                .cornerRadius(100)
                                .overlay(Capsule().stroke(Color.borderColor, lineWidth: 1))
                        }
                        .disabled(isTyping)
                        .opacity(isTyping ? 0.4 : 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            // Text input row
            HStack(spacing: 10) {
                // Mic button
                Button(action: {}) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.textTertiary)
                        .frame(width: 44, height: 44)
                        .background(Color.surfaceElevated)
                        .cornerRadius(14)
                }

                // Text field with send button
                ZStack(alignment: .trailing) {
                    TextField("Message your trainer...", text: $inputText)
                        .font(.system(size: 14))
                        .foregroundColor(.textPrimary)
                        .tint(.ember)
                        .focused($focused)
                        .disabled(isTyping)
                        .padding(.leading, 16)
                        .padding(.trailing, 50)
                        .frame(height: 44)
                        .background(Color.surfaceElevated)
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(focused ? Color.ember.opacity(0.4) : Color.borderColor, lineWidth: 1)
                        )
                        .onSubmit { sendMessage(inputText) }

                    Button(action: { sendMessage(inputText) }) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isTyping ? Color.borderColor : Color.ember)
                            .cornerRadius(9)
                            .shadow(color: inputText.isEmpty ? .clear : Color.ember.opacity(0.3), radius: 8)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isTyping)
                    .padding(.trailing, 7)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            Color.background.opacity(0.9)
                .background(.ultraThinMaterial.opacity(0.4))
        )
    }
}
