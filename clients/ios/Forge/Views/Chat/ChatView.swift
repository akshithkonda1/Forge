import SwiftUI

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @State private var inputText = ""
    @State private var isTyping = false
    @FocusState private var isInputFocused: Bool

    private let quickActions = [
        "How should I train today?",
        "I'm not feeling it",
        "Explain my sleep data",
        "Adjust my plan",
        "I have an injury/pain",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(store.chatMessages.enumerated()), id: \.element.id) { index, msg in
                            MessageBubble(message: msg, index: index, total: store.chatMessages.count)
                        }

                        if isTyping {
                            TypingIndicator()
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: store.chatMessages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: isTyping) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            // Bottom input area
            VStack(spacing: 0) {
                // Quick actions
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickActions, id: \.self) { action in
                            Button {
                                sendMessage(action)
                            } label: {
                                Text(action)
                                    .font(.system(size: 12))
                                    .foregroundColor(.textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.clear)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.forgeBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(isTyping)
                            .opacity(isTyping ? 0.4 : 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                }

                // Input row
                HStack(spacing: 8) {
                    Button { } label: {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.textTertiary)
                            .frame(width: 44, height: 44)
                            .background(Color.forgeSurfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 0) {
                        TextField("Message your trainer...", text: $inputText)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .focused($isInputFocused)
                            .onSubmit { sendMessage(inputText) }
                            .disabled(isTyping)

                        Button {
                            sendMessage(inputText)
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(
                                    !inputText.trimmingCharacters(in: .whitespaces).isEmpty && !isTyping
                                    ? Color.ember : Color.clear
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isTyping)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .frame(height: 44)
                    .background(Color.forgeSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isInputFocused ? Color.ember.opacity(0.5) : Color.forgeBorder, lineWidth: 1)
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 4)
            }
            .background(
                Color.forgeBackground.opacity(0.8)
                    .background(.ultraThinMaterial)
            )
            .overlay(
                Rectangle().frame(height: 1).foregroundColor(.forgeBorder),
                alignment: .top
            )
        }
        .background(Color.forgeBackground)
    }

    private var chatHeader: some View {
        GlassHeader {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.ember.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "cpu")
                                .font(.system(size: 16))
                                .foregroundColor(.ember)
                        )

                    Circle()
                        .fill(Color.forgeSuccess)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.forgeBackground, lineWidth: 2))
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Forge AI")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)

                    HStack(spacing: 4) {
                        Circle().fill(Color.ember).frame(width: 6, height: 6)
                        Text("Online")
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()
            }
        }
    }

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTyping else { return }

        inputText = ""
        isInputFocused = false

        isTyping = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            store.sendUserMessage(trimmed)
            isTyping = false
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    let index: Int
    let total: Int

    private var isTrainer: Bool { message.role == .trainer }
    private var staggerIndex: Int { min(4, max(0, total - 1 - index)) }

    var body: some View {
        HStack {
            if !isTrainer { Spacer(minLength: 40) }

            VStack(alignment: isTrainer ? .leading : .trailing, spacing: 4) {
                // Bubble
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .lineSpacing(3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isTrainer ? Color.forgeSurfaceElevated : Color.ember.opacity(0.9))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )

                // Rich card
                if let card = message.richCard {
                    if card.type == .workoutPlan, let data = card.workoutData {
                        WorkoutRichCard(data: data)
                    } else if card.type == .dataChart, let data = card.chartData {
                        DataChartRichCard(data: data)
                    }
                }

                // Timestamp
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: isTrainer ? .leading : .trailing)

            if isTrainer { Spacer(minLength: 40) }
        }
        .transition(
            isTrainer
            ? .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                removal: .opacity
            )
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            )
        )
        .animation(FDS.Spring.hero.delay(Double(staggerIndex) * 0.04), value: message.id)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.textTertiary)
                        .frame(width: 6, height: 6)
                        .opacity(0.3 + 0.7 * sin(phase + Double(i) * 0.8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.forgeSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

// MARK: - Workout Rich Card

struct WorkoutRichCard: View {
    let data: WorkoutCardData
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(data.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                        Text("\(data.duration) min")
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 11))
                        Text("\(data.exercises.count) exercises")
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
            }
            .padding(14)

            // Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack {
                    Text(expanded ? "Hide exercises" : "View exercises")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.forgeSurfaceElevated)
            }
            .buttonStyle(.plain)

            // Exercises
            if expanded {
                VStack(spacing: 8) {
                    ForEach(Array(data.exercises.enumerated()), id: \.offset) { i, ex in
                        HStack {
                            Text("\(i + 1)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.ember)
                                .frame(width: 20, height: 20)
                                .background(Color.ember.opacity(0.1))
                                .clipShape(Circle())

                            Text(ex.name)
                                .font(.system(size: 12))
                                .foregroundColor(.white)

                            Spacer()

                            Text("\(ex.sets) × \(ex.reps)")
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
                .padding(14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Start button
            Button {
                // Start workout action
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                    Text("Start This Workout")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.ember)
                .shadow(color: .ember.opacity(0.25), radius: 10)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .background(Color.forgeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.forgeBorder, lineWidth: 1)
        )
        .overlay(
            Rectangle().fill(Color.ember).frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Data Chart Rich Card

struct DataChartRichCard: View {
    let data: ChartCardData

    private var chartColor: Color {
        Color(hex: data.color)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12))
                    .foregroundColor(chartColor)

                Text(data.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            SparklineChart(values: data.values, color: chartColor, height: 44)
                .padding(.vertical, 4)

            Text(data.insight)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
                .lineSpacing(2)
        }
        .padding(14)
        .background(Color.forgeSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.forgeBorder, lineWidth: 1)
        )
    }
}
