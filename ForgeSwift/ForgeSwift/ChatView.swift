import SwiftUI
import AVFoundation

// MARK: - Quick actions (mirrors QUICK_ACTIONS in chat-page.tsx)

private let quickActions = [
    "What should we do today?",
    "Not feeling it today",
    "How'd I sleep?",
    "Am I making progress?",
    "Something hurts",
    "Change my plan",
]

// MARK: - Haptic Feedback Manager

final class HapticManager {
    static let shared = HapticManager()
    
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    
    private init() {
        impact.prepare()
        selection.prepare()
        notification.prepare()
    }
    
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    func selectionChanged() {
        selection.selectionChanged()
    }
    
    func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notification.notificationOccurred(type)
    }
}

// MARK: - Speech Recognition Manager (Basic wrapper)

@MainActor
final class SpeechManager: ObservableObject {
    @Published var recognizedText: String = ""
    @Published var isListening: Bool = false
    @Published var error: String?
    
    func startListening() {
        isListening = true
        // In production, integrate with Speech framework
        // For now, simulate transcription
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.recognizedText = "What should we do today?"
            self.isListening = false
            HapticManager.shared.notification(.success)
        }
    }
    
    func stopListening() {
        isListening = false
    }
}

// MARK: - Empty State View

struct ChatEmptyStateView: View {
    let onQuickActionTap: (String) -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Animated AI Icon
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ember.opacity(0.2), Color.ember.opacity(0.05), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.ember.opacity(0.15), Color.ember.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(LinearGradient.ember)
            }
            
            VStack(spacing: 8) {
                Text("Hey, ready to train?")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Text("I'm your AI coach. Ask me anything about\nyour workouts, recovery, or progress.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            // Suggested prompts
            VStack(alignment: .leading, spacing: 12) {
                Text("Try asking:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 4)
                
                ForEach(["What should we do today?", "How'd I sleep?", "Am I making progress?"], id: \.self) { prompt in
                    Button(action: { onQuickActionTap(prompt) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundColor(.ember)
                            
                            Text(prompt)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            
                            Spacer()
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textTertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.surfaceElevated)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.borderColor.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Chat Page (mirrors chat-page.tsx)

struct ChatView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var speechManager = SpeechManager()
    
    @State private var inputText = ""
    @State private var isTyping = false
    @State private var scrollProxy: ScrollViewProxy? = nil
    @State private var showScrollToBottom = false
    @State private var isNearBottom = true
    
    // Keyboard management
    @FocusState private var isInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        ZStack {
            // Subtle background gradient
            LinearGradient(
                colors: [
                    Color.background,
                    Color.background.opacity(0.98),
                    Color.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                ChatHeaderView()

                // Messages with enhanced scroll behavior
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            if store.chatMessages.isEmpty {
                                // Empty state
                                ChatEmptyStateView { prompt in
                                    inputText = prompt
                                    isInputFocused = true
                                }
                                .frame(height: geometry.size.height)
                            } else {
                                LazyVStack(spacing: 20) {
                                    // Top spacing for better visual balance
                                    Color.clear.frame(height: 8)
                                    
                                    ForEach(store.chatMessages) { msg in
                                        MessageBubbleView(message: msg)
                                            .id(msg.id)
                                            .transition(.asymmetric(
                                                insertion: .scale(scale: 0.8).combined(with: .opacity),
                                                removal: .opacity
                                            ))
                                    }
                                    
                                    if isTyping {
                                        TypingIndicatorView()
                                            .id("typing")
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                    
                                    // Bottom anchor with padding
                                    Color.clear.frame(height: 16).id("bottom")
                                }
                                .padding(.horizontal, 18)
                            }
                        }
                        .background(
                            GeometryReader { scrollGeometry in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: scrollGeometry.frame(in: .named("scroll")).origin
                                )
                            }
                        )
                        .coordinateSpace(name: "scroll")
                        .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                            // Detect if user is near bottom
                            isNearBottom = value.y > -100
                        }
                        .onChange(of: store.chatMessages.count) {
                            scrollToBottom(proxy: proxy, animated: true)
                        }
                        .onChange(of: isTyping) {
                            if isTyping {
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                        }
                        .onAppear {
                            scrollProxy = proxy
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                scrollToBottom(proxy: proxy, animated: false)
                            }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            // Scroll to bottom button
                            if !isNearBottom && !store.chatMessages.isEmpty {
                                ScrollToBottomButton {
                                    scrollToBottom(proxy: proxy, animated: true)
                                    HapticManager.shared.impact(.light)
                                }
                                .padding(.trailing, 20)
                                .padding(.bottom, 20)
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }
                .background(Color.background)

                // Input area
                ChatInputAreaView(
                    inputText: $inputText,
                    isTyping: $isTyping,
                    isInputFocused: $isInputFocused,
                    speechManager: speechManager
                )
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Refresh when app becomes active
                store.refreshDailyData()
            }
        }
        .onChange(of: speechManager.recognizedText) { _, newText in
            if !newText.isEmpty {
                inputText = newText
                speechManager.recognizedText = ""
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

// MARK: - Scroll to Bottom Button

struct ScrollToBottomButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.surfaceElevated)
                    .frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
                
                Circle()
                    .stroke(Color.borderColor, lineWidth: 1)
                    .frame(width: 44, height: 44)
                
                Image(systemName: "arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.ember, .emberLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Header

struct ChatHeaderView: View {
    @State private var pulse = false
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 14) {
            // AI Avatar with glow effect
            ZStack(alignment: .bottomTrailing) {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.ember.opacity(0.3), Color.ember.opacity(0.05), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 26
                        )
                    )
                    .frame(width: 52, height: 52)
                    .blur(radius: 8)
                
                // Main avatar circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.ember.opacity(0.2), Color.ember.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.ember.opacity(0.6), Color.ember.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.ember, Color.ember.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Enhanced online indicator
                ZStack {
                    Circle()
                        .fill(Color.background)
                        .frame(width: 14, height: 14)
                    
                    Circle()
                        .fill(Color.success)
                        .frame(width: 11, height: 11)
                    
                    Circle()
                        .fill(Color.success.opacity(0.4))
                        .frame(width: 11, height: 11)
                        .scaleEffect(pulse ? 1.6 : 1)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.5).repeatForever(autoreverses: false), value: pulse)
                }
                .offset(x: 3, y: 3)
            }
            .onAppear { pulse = true }

            // Title and status
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Forge AI")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    // Verified badge
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.ember, Color.ember.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 6, height: 6)
                    Text("Active now")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            
            Spacer()
            
            // Readiness indicator chip
            HStack(spacing: 6) {
                Circle()
                    .fill(readinessColor)
                    .frame(width: 8, height: 8)
                Text("\(store.readiness.overall)%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.surfaceElevated)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(readinessColor.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [Color.background, Color.background.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Frosted glass effect
                .background(.ultraThinMaterial.opacity(0.8))
            }
        )
        .overlay(
            // Bottom border with gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.borderColor.opacity(0.3), Color.borderColor, Color.borderColor.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    private var readinessColor: Color {
        let score = store.readiness.overall
        if score >= 80 { return .success }
        if score >= 60 { return .ember }
        return .orange
    }
}

// MARK: - Message Bubble (mirrors MessageBubble in chat-page.tsx)

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var appear = false
    @State private var showTimestamp = false
    
    var isTrainer: Bool { message.role == .trainer }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if !isTrainer { Spacer(minLength: 60) }
            
            // Trainer avatar (only for trainer messages)
            if isTrainer {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.ember.opacity(0.15), Color.ember.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LinearGradient.ember)
                }
                .offset(y: -4)
                .accessibilityLabel("Forge AI")
            }

            VStack(alignment: isTrainer ? .leading : .trailing, spacing: 6) {
                // Text bubble with enhanced styling
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showTimestamp.toggle()
                    }
                    HapticManager.shared.selectionChanged()
                }) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(message.content)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(isTrainer ? .textPrimary : .white)
                            .lineSpacing(4)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .textSelection(.enabled)
                    }
                    .background(
                        Group {
                            if isTrainer {
                                Color.surfaceElevated
                            } else {
                                LinearGradient(
                                    colors: [Color.ember, Color.ember.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            }
                        }
                    )
                    .cornerRadius(20)
                    .cornerRadius(isTrainer ? 6 : 20, corners: isTrainer ? .bottomLeft : .bottomRight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isTrainer ? Color.borderColor.opacity(0.5) : Color.clear,
                                lineWidth: isTrainer ? 1 : 0
                            )
                            .cornerRadius(isTrainer ? 6 : 20, corners: isTrainer ? .bottomLeft : .bottomRight)
                    )
                    .shadow(
                        color: isTrainer ? Color.black.opacity(0.03) : Color.ember.opacity(0.25),
                        radius: isTrainer ? 2 : 8,
                        x: 0,
                        y: isTrainer ? 1 : 2
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(isTrainer ? "Forge AI" : "You") said: \(message.content)")
                .accessibilityHint("Tap to show timestamp")

                // Rich card
                if let card = message.richCard {
                    RichCardView(card: card)
                        .padding(.top, 4)
                }

                // Timestamp (shows on tap)
                if showTimestamp {
                    HStack(spacing: 4) {
                        Text(formatTime(message.timestamp))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textMuted)
                        
                        if isTrainer {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.success.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 2)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.05)) {
                    appear = true
                }
            }

            if isTrainer { Spacer(minLength: 60) }
        }
        .contextMenu {
            Button(action: {
                UIPasteboard.general.string = message.content
                HapticManager.shared.notification(.success)
            }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            
            if isTrainer {
                Button(action: {
                    // Could implement share functionality
                    HapticManager.shared.selectionChanged()
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
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
            // Header with gradient accent
            VStack(alignment: .leading, spacing: 0) {
                // Top accent bar
                Rectangle()
                    .fill(LinearGradient.ember)
                    .frame(height: 3)
                
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: [Color.ember.opacity(0.15), Color.ember.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "dumbbell.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LinearGradient.ember)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.workoutName ?? "Workout Plan")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        
                        HStack(spacing: 12) {
                            Label("\(card.workoutDuration ?? 0) min", systemImage: "clock.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                            
                            Label("\(card.workoutExercises?.count ?? 0) exercises", systemImage: "list.bullet")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { expanded.toggle() } }) {
                        Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.ember, Color.ember.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                .padding(16)
            }

            // Exercise list (expanded)
            if expanded, let exercises = card.workoutExercises {
                Divider()
                    .background(Color.borderColor.opacity(0.5))
                
                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack(spacing: 12) {
                            // Exercise number badge
                            ZStack {
                                Circle()
                                    .fill(Color.ember.opacity(0.1))
                                    .frame(width: 26, height: 26)
                                
                                Text("\(idx+1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.ember)
                            }
                            
                            Text(ex.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                            
                            Spacer()
                            
                            Text("\(ex.sets) × \(ex.reps)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.surface)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        
                        if idx < exercises.count - 1 {
                            Divider()
                                .background(Color.borderColor.opacity(0.3))
                                .padding(.leading, 54)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()
                .background(Color.borderColor.opacity(0.5))

            // Start button with gradient
            Button(action: { store.startWorkout(); store.activeTab = .workout }) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                    
                    Text("Start This Workout")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient.ember)
                .cornerRadius(12)
                .shadow(color: Color.ember.opacity(0.3), radius: 8, x: 0, y: 2)
            }
            .padding(12)
        }
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderColor.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
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
        VStack(alignment: .leading, spacing: 0) {
            // Header with accent
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [chartColor.opacity(0.6), chartColor.opacity(0.3)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(chartColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(chartColor)
                    }
                    
                    Text(card.chartTitle ?? "Trend")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    Spacer()
                }
                .padding(14)
            }

            // Chart area with gradient background
            VStack(alignment: .leading, spacing: 12) {
                // Bar chart
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(values.enumerated()), id: \.offset) { idx, val in
                        let normalised = maxVal > minVal ? (val - minVal) / (maxVal - minVal) : 1
                        
                        VStack(spacing: 4) {
                            Spacer()
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            chartColor.opacity(0.5 + 0.5 * normalised),
                                            chartColor.opacity(0.3 + 0.4 * normalised)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: appear ? max(8, 50 * CGFloat(normalised)) : 4)
                                .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(idx) * 0.06), value: appear)
                        }
                    }
                }
                .frame(height: 50)
                
                // Insight text
                if let insight = card.chartInsight {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 12))
                            .foregroundColor(chartColor.opacity(0.7))
                        
                        Text(insight)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .lineSpacing(3)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(chartColor.opacity(0.04))
            )
            .padding(12)
        }
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.borderColor.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        .onAppear {
            withAnimation { appear = true }
        }
    }
}

// MARK: - Typing Indicator with Thinking States

struct TypingIndicatorView: View {
    @State private var animate = false
    @State private var thinkingState: ThinkingState = .analyzing
    @State private var showThinkingText = false
    
    enum ThinkingState: String, CaseIterable {
        case analyzing = "Analyzing your question..."
        case thinking = "Thinking..."
        case processing = "Processing data..."
        case formulating = "Formulating response..."
        case typing = ""
        
        var icon: String {
            switch self {
            case .analyzing: return "brain.head.profile"
            case .thinking: return "lightbulb.fill"
            case .processing: return "gearshape.2.fill"
            case .formulating: return "text.bubble.fill"
            case .typing: return ""
            }
        }
        
        var color: Color {
            switch self {
            case .analyzing: return .ember
            case .thinking: return .purple
            case .processing: return .blue
            case .formulating: return .success
            case .typing: return .textSecondary
            }
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Trainer avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.ember.opacity(0.15), Color.ember.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                
                Image(systemName: "flame.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LinearGradient.ember)
            }
            .offset(y: -4)
            
            VStack(alignment: .leading, spacing: 8) {
                // Thinking state text (appears above the dots)
                if showThinkingText && thinkingState != .typing {
                    HStack(spacing: 6) {
                        Image(systemName: thinkingState.icon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(thinkingState.color)
                        
                        Text(thinkingState.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(thinkingState.color.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(thinkingState.color.opacity(0.2), lineWidth: 1)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Typing dots indicator
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        thinkingState.color.opacity(0.8),
                                        thinkingState.color.opacity(0.6)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 8, height: 8)
                            .scaleEffect(animate ? 1.0 : 0.6)
                            .opacity(animate ? 1 : 0.4)
                            .animation(
                                .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(i) * 0.2),
                                value: animate
                            )
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.surfaceElevated)
                .cornerRadius(20)
                .cornerRadius(6, corners: .bottomLeft)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.borderColor.opacity(0.5), lineWidth: 1)
                        .cornerRadius(6, corners: .bottomLeft)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
            }

            Spacer()
        }
        .onAppear {
            animate = true
            
            // Cycle through thinking states for a more human feel
            withAnimation(.easeInOut(duration: 0.3).delay(0.1)) {
                showThinkingText = true
            }
            
            // State progression timeline
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    thinkingState = .thinking
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    thinkingState = .processing
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    thinkingState = .formulating
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showThinkingText = false
                    thinkingState = .typing
                }
            }
        }
    }
}

// MARK: - Aurora Borealis Voice Orb

struct SiriVoiceOrbView: View {
    @Binding var isListening: Bool
    @State private var animationPhase: CGFloat = 0
    @State private var wavePhase: CGFloat = 0
    @State private var particlePhase: CGFloat = 0
    @State private var auroraFlow: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Deep space background
            ZStack {
                Color.black
                    .ignoresSafeArea()
                
                // Starfield effect
                ForEach(0..<50) { index in
                    Circle()
                        .fill(Color.white.opacity(Double.random(in: 0.3...0.8)))
                        .frame(width: CGFloat.random(in: 1...3))
                        .position(
                            x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                            y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                        )
                        .opacity(0.4 + sin(animationPhase + Double(index) * 0.5) * 0.3)
                }
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isListening = false
                }
            }
            
            VStack(spacing: 40) {
                Spacer()
                
                // Aurora Borealis Orb
                ZStack {
                    // Atmospheric glow base
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.cyan.opacity(0.2),
                                    Color.purple.opacity(0.15),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: 50,
                                endRadius: 200
                            )
                        )
                        .frame(width: 400, height: 400)
                        .blur(radius: 30)
                    
                    // Flowing aurora layers (Northern Lights effect)
                    ForEach(0..<6) { layer in
                        AuroraWaveLayer(
                            phase: auroraFlow + Double(layer) * 0.7,
                            color: auroraColor(for: layer),
                            amplitude: 30 + CGFloat(layer) * 8,
                            frequency: 2.0 + Double(layer) * 0.3,
                            offset: CGFloat(layer) * 15
                        )
                        .frame(width: 280, height: 280)
                        .blur(radius: 15 - CGFloat(layer) * 2)
                        .blendMode(.screen)
                        .opacity(0.6 - Double(layer) * 0.08)
                    }
                    
                    // Ethereal particles floating through
                    ForEach(0..<20) { index in
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        particleColor(for: index).opacity(0.8),
                                        particleColor(for: index).opacity(0.3),
                                        Color.clear
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 10
                                )
                            )
                            .frame(width: CGFloat.random(in: 4...12))
                            .offset(
                                x: 120 * cos(particlePhase + Double(index) * 0.628 + auroraFlow * 0.5),
                                y: 120 * sin(particlePhase + Double(index) * 0.628 + auroraFlow * 0.3)
                            )
                            .blur(radius: 3)
                            .opacity(0.4 + abs(sin(particlePhase + Double(index) * 0.8)) * 0.4)
                    }
                    
                    // Core orb with flowing gradient
                    ZStack {
                        // Prismatic core
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [
                                        Color(hex: "00FFF0"), // Cyan
                                        Color(hex: "0080FF"), // Blue
                                        Color(hex: "8000FF"), // Purple
                                        Color(hex: "FF0080"), // Magenta
                                        Color(hex: "FF6B00"), // Orange
                                        Color(hex: "00FFF0")  // Cyan (loop)
                                    ],
                                    center: .center,
                                    angle: .degrees(auroraFlow * 50)
                                )
                            )
                            .frame(width: 240, height: 240)
                            .blur(radius: 40)
                            .opacity(0.6)
                        
                        // Waveform visualization
                        HStack(spacing: 5) {
                            ForEach(0..<24) { index in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.95),
                                                waveformColor(for: index).opacity(0.9),
                                                waveformColor(for: index).opacity(0.6)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 3)
                                    .frame(height: waveformHeight(for: index))
                                    .shadow(color: waveformColor(for: index).opacity(0.8), radius: 4)
                            }
                        }
                        .frame(width: 180, height: 100)
                    }
                    .clipShape(Circle())
                    .overlay(
                        // Prismatic rim
                        Circle()
                            .stroke(
                                AngularGradient(
                                    colors: [
                                        Color.cyan.opacity(0.8),
                                        Color.blue.opacity(0.7),
                                        Color.purple.opacity(0.7),
                                        Color.pink.opacity(0.7),
                                        Color.cyan.opacity(0.8)
                                    ],
                                    center: .center,
                                    angle: .degrees(auroraFlow * 30)
                                ),
                                lineWidth: 2.5
                            )
                    )
                    .frame(width: 240, height: 240)
                    .shadow(color: Color.cyan.opacity(0.7), radius: 50, x: 0, y: 0)
                    .shadow(color: Color.purple.opacity(0.6), radius: 70, x: 0, y: 0)
                    .shadow(color: Color.blue.opacity(0.5), radius: 90, x: 0, y: 0)
                    
                    // Light rays emanating
                    ForEach(0..<8) { ray in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        rayColor(for: ray).opacity(0.6),
                                        rayColor(for: ray).opacity(0.1),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 2, height: 60)
                            .blur(radius: 4)
                            .offset(y: -150)
                            .rotationEffect(.degrees(Double(ray) * 45 + auroraFlow * 20))
                            .opacity(0.5 + abs(sin(animationPhase + Double(ray) * 0.5)) * 0.3)
                    }
                }
                
                // Status text with aurora glow
                VStack(spacing: 12) {
                    Text("Listening...")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cyan, Color.white, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: Color.cyan.opacity(0.8), radius: 10)
                    
                    Text("Tap anywhere to cancel")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Ethereal cancel button
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isListening = false
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                        Text("Cancel")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.cyan.opacity(0.9)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.cyan.opacity(0.6),
                                            Color.purple.opacity(0.4),
                                            Color.cyan.opacity(0.6)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1.5
                                )
                        }
                    )
                    .shadow(color: Color.cyan.opacity(0.3), radius: 15, x: 0, y: 5)
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                animationPhase = .pi * 2
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                wavePhase = .pi * 2
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                particlePhase = .pi * 2
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                auroraFlow = .pi * 2
            }
        }
        .transition(.opacity)
    }
    
    // Aurora color palette - inspired by Northern Lights
    func auroraColor(for layer: Int) -> Color {
        let colors: [Color] = [
            Color(hex: "00FFF0"), // Bright cyan
            Color(hex: "00CCFF"), // Sky blue
            Color(hex: "0080FF"), // Deep blue
            Color(hex: "6000FF"), // Purple
            Color(hex: "CC00FF"), // Magenta
            Color(hex: "00FFAA")  // Teal
        ]
        return colors[layer % colors.count]
    }
    
    func particleColor(for index: Int) -> Color {
        let colors: [Color] = [
            Color.cyan,
            Color.blue,
            Color.purple,
            Color(hex: "00FFAA"),
            Color.white
        ]
        return colors[index % colors.count]
    }
    
    func waveformColor(for index: Int) -> Color {
        let progress = Double(index) / 24.0
        if progress < 0.33 {
            return Color.cyan
        } else if progress < 0.66 {
            return Color.purple
        } else {
            return Color(hex: "FF0080")
        }
    }
    
    func waveformHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 8
        let wave = abs(sin(wavePhase + Double(index) * 0.5)) * 70
        let pulse = abs(sin(animationPhase * 2 + Double(index) * 0.3)) * 20
        return base + wave + pulse
    }
    
    func rayColor(for ray: Int) -> Color {
        let colors: [Color] = [
            Color.cyan,
            Color.blue,
            Color.purple,
            Color(hex: "FF0080")
        ]
        return colors[ray % colors.count]
    }
}

// MARK: - Aurora Wave Layer (Flowing Northern Lights Effect)

struct AuroraWaveLayer: View {
    let phase: Double
    let color: Color
    let amplitude: CGFloat
    let frequency: Double
    let offset: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2
                
                path.move(to: CGPoint(x: 0, y: midY))
                
                for x in stride(from: 0, through: width, by: 2) {
                    let relativeX = x / width
                    let sine = sin((relativeX * frequency + phase) * .pi * 2)
                    let y = midY + sine * amplitude + offset
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                // Close the path for fill
                path.addLine(to: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(0.6),
                        color.opacity(0.3),
                        color.opacity(0.1),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

// MARK: - Chat Input Area

struct ChatInputAreaView: View {
    @EnvironmentObject var store: AppStore
    @Binding var inputText: String
    @Binding var isTyping: Bool
    @FocusState.Binding var isInputFocused: Bool
    @ObservedObject var speechManager: SpeechManager
    
    @State private var showQuickActions = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isTyping else { return }
        
        // Haptic feedback on send
        HapticManager.shared.impact(.light)

        let userMsg = ChatMessage(id: "user-\(Date().timeIntervalSince1970)",
                                  role: .user, content: trimmed, timestamp: Date())
        store.addMessage(userMsg)
        inputText = ""
        isTyping = true
        
        // Hide quick actions when user starts chatting
        withAnimation(.easeOut(duration: 0.3)) {
            showQuickActions = false
        }

        // More sophisticated, human-like response timing
        let wordCount = trimmed.split(separator: " ").count
        let hasQuestionMark = trimmed.contains("?")
        let isComplex = trimmed.lowercased().contains("why") || 
                       trimmed.lowercased().contains("how") ||
                       trimmed.lowercased().contains("explain")
        
        // Base thinking/analyzing time (0.8-1.2s for initial processing)
        let thinkingTime = Double.random(in: 0.8...1.2)
        
        // Processing time based on message complexity
        var processingTime: Double
        if isComplex {
            // Complex questions need more "thought"
            processingTime = Double.random(in: 1.8...2.8)
        } else if wordCount <= 3 {
            // Short messages are quick
            processingTime = Double.random(in: 0.6...1.0)
        } else if wordCount <= 8 {
            // Medium messages
            processingTime = Double.random(in: 1.0...1.8)
        } else {
            // Longer messages
            processingTime = Double.random(in: 1.5...2.5)
        }
        
        // Formulation time (0.4-0.8s for crafting response)
        let formulationTime = Double.random(in: 0.4...0.8)
        
        // Questions get slightly faster responses (more engaged)
        if hasQuestionMark && !isComplex {
            processingTime *= 0.85
        }
        
        // Typing time (simulating actual typing - ~50-80ms per character)
        let (content, _) = store.trainerResponse(for: trimmed)
        let typingTime = Double(content.count) * Double.random(in: 0.05...0.08)
        
        // Total delay with natural variance
        let totalDelay = thinkingTime + processingTime + formulationTime + min(typingTime, 1.5)
        
        // Add final tiny random variation for naturalness
        let finalDelay = totalDelay + Double.random(in: -0.15...0.2)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + max(finalDelay, 1.5)) {
            let (content, richCard) = store.trainerResponse(for: trimmed)
            let trainerMsg = ChatMessage(id: "trainer-\(Date().timeIntervalSince1970)",
                                          role: .trainer, content: content,
                                          timestamp: Date(), richCard: richCard)
            store.addMessage(trainerMsg)
            isTyping = false
            
            // Success haptic when response arrives
            HapticManager.shared.notification(.success)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Separator with subtle gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.borderColor.opacity(0.3), Color.borderColor, Color.borderColor.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // Quick actions with improved styling
            if showQuickActions && !isInputFocused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(quickActions, id: \.self) { action in
                            ChatQuickActionButton(
                                action: action,
                                isDisabled: isTyping,
                                onTap: {
                                    sendMessage(action)
                                    HapticManager.shared.selectionChanged()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Text input row with enhanced design
            HStack(spacing: 12) {
                // Microphone button with gradient background
                Button(action: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if speechManager.isListening {
                            speechManager.stopListening()
                        } else {
                            speechManager.startListening()
                        }
                    }
                    HapticManager.shared.impact(.medium)
                }) {
                    ZStack {
                        Circle()
                            .fill(
                                speechManager.isListening
                                    ? LinearGradient(
                                        colors: [Color.danger, Color.danger.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                    : LinearGradient(
                                        colors: [Color.ember.opacity(0.15), Color.ember.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: speechManager.isListening ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(
                                speechManager.isListening
                                    ? LinearGradient(colors: [.white], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(
                                        colors: [Color.ember, Color.ember.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                            )
                            .symbolEffect(.pulse, isActive: speechManager.isListening)
                    }
                }
                .disabled(isTyping)
                .opacity(isTyping ? 0.5 : 1)
                .accessibilityLabel(speechManager.isListening ? "Stop recording" : "Start voice input")

                // Enhanced text field
                ZStack(alignment: .trailing) {
                    // Background with subtle gradient
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(
                                    isInputFocused 
                                        ? LinearGradient(
                                            colors: [Color.ember.opacity(0.5), Color.ember.opacity(0.3)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        : LinearGradient(
                                            colors: [Color.borderColor.opacity(0.6), Color.borderColor.opacity(0.4)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: isInputFocused ? Color.ember.opacity(0.1) : Color.black.opacity(0.02),
                            radius: isInputFocused ? 8 : 2,
                            x: 0,
                            y: isInputFocused ? 2 : 1
                        )
                    
                    TextField("Ask me anything...", text: $inputText, axis: .vertical)
                        .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 17 : 15))
                        .foregroundColor(.textPrimary)
                        .tint(.ember)
                        .focused($isInputFocused)
                        .disabled(isTyping)
                        .padding(.leading, 18)
                        .padding(.trailing, 54)
                        .padding(.vertical, 12)
                        .lineLimit(1...4)
                        .onSubmit {
                            sendMessage(inputText)
                        }
                        .accessibilityLabel("Message input")
                        .accessibilityHint("Type your message to Forge AI")

                    // Send button with dynamic styling
                    Button(action: {
                        sendMessage(inputText)
                    }) {
                        ZStack {
                            Circle()
                                .fill(
                                    inputText.trimmingCharacters(in: .whitespaces).isEmpty || isTyping
                                        ? AnyShapeStyle(Color.borderColor.opacity(0.3))
                                        : AnyShapeStyle(LinearGradient(
                                            colors: [Color.ember, Color.ember.opacity(0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                )
                                .frame(width: 34, height: 34)
                            
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .shadow(
                            color: inputText.isEmpty ? .clear : Color.ember.opacity(0.35),
                            radius: 8,
                            x: 0,
                            y: 2
                        )
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isTyping)
                    .padding(.trailing, 8)
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Send message")
                }
                .frame(height: 48)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color.background.opacity(0.98), Color.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .background(.ultraThinMaterial.opacity(0.6))
            }
        )
        .overlay(
            // Siri Voice Orb Overlay
            Group {
                if speechManager.isListening {
                    SiriVoiceOrbView(isListening: $speechManager.isListening)
                }
            }
        )
    }
}

// MARK: - Chat Quick Action Button

struct ChatQuickActionButton: View {
    let action: String
    let isDisabled: Bool
    let onTap: () -> Void
    
    var iconName: String {
        if action.lowercased().contains("sleep") {
            return "moon.fill"
        } else if action.lowercased().contains("hurt") {
            return "heart.text.square.fill"
        } else if action.lowercased().contains("progress") {
            return "chart.line.uptrend.xyaxis"
        } else if action.lowercased().contains("not feeling") {
            return "battery.25"
        } else if action.lowercased().contains("change") {
            return "arrow.triangle.2.circlepath"
        } else {
            return "sparkles"
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .font(.system(size: 11))
                
                Text(action)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isDisabled ? .textMuted : .textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule()
                    .fill(Color.surfaceElevated)
            )
            .overlay(
                Capsule()
                    .stroke(Color.borderColor.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 2, x: 0, y: 1)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(action)
        .accessibilityHint("Send quick message")
    }
}
