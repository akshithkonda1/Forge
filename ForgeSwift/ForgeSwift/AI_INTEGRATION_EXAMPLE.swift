import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Example App Entry Point with AI Setup
// NOTE: This is an example. Remove @main if you're using ForgeSwiftApp as your actual entry point.

// Example app structure showing how to integrate AI features
struct ForgeApp_Example: App {
    @StateObject private var appStore = AppStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appStore)
                .task {
                    // Check AI availability on launch
                    await checkAIStatus()
                }
        }
    }
    
    private func checkAIStatus() async {
        if appStore.aiModelAvailable {
            print("✅ Apple Intelligence available - using Foundation Models")
        } else {
            print("⚠️ Apple Intelligence unavailable - using rule-based fallback")
        }
    }
}

// MARK: - Enhanced Chat View with AI Features

struct EnhancedChatView: View {
    @EnvironmentObject var appStore: AppStore
    @State private var messageText = ""
    @State private var showingAISettings = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // AI Status Banner
                if #available(iOS 18.2, *) {
                    AIStatusBanner(isAvailable: appStore.aiModelAvailable)
                }
                
                // Messages
                MessagesScrollView(
                    messages: appStore.chatMessages,
                    isGenerating: appStore.isGeneratingResponse
                )
                
                Divider()
                
                // Input Area
                ChatInputArea(
                    messageText: $messageText,
                    isInputFocused: $isInputFocused,
                    isGenerating: appStore.isGeneratingResponse,
                    onSend: sendMessage
                )
            }
            .navigationTitle("AI Trainer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAISettings = true
                    } label: {
                        Image(systemName: "brain.head.profile")
                    }
                }
            }
            .sheet(isPresented: $showingAISettings) {
                AISettingsView()
            }
        }
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        messageText = ""
        isInputFocused = false
        
        Task {
            await appStore.sendMessage(text)
        }
    }
}

// MARK: - AI Status Banner

@available(iOS 18.2, *)
struct AIStatusBanner: View {
    let isAvailable: Bool
    @State private var showingDetails = false
    
    var body: some View {
        Button {
            showingDetails = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isAvailable ? "sparkles" : "exclamationmark.triangle")
                    .foregroundStyle(isAvailable ? .blue : .orange)
                
                Text(isAvailable ? "Powered by Apple Intelligence" : "Using Offline Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .alert("AI Model Status", isPresented: $showingDetails) {
            Button("OK") { }
        } message: {
            if isAvailable {
                Text("Your trainer is powered by Apple's on-device language model. Responses are personalized based on your biometric data and training history. All processing happens on your device for privacy.")
            } else {
                Text("Apple Intelligence is not available on this device or is not enabled. Your trainer is using a rule-based system that still provides personalized coaching based on your data.")
            }
        }
    }
}

// MARK: - Messages Scroll View

struct MessagesScrollView: View {
    let messages: [ChatMessage]
    let isGenerating: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        ExampleMessageBubbleView(message: message)
                            .id(message.id)
                    }
                    
                    if isGenerating {
                        ExampleTypingIndicatorView()
                            .id("typing")
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: isGenerating) {
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation {
            if isGenerating {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message Bubble

struct ExampleMessageBubbleView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 60)
            } else {
                // Trainer avatar
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.blue.opacity(0.1)))
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Message content
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                    .textSelection(.enabled)
                
                // Rich card if present
                if let richCard = message.richCard {
                    ExampleRichCardView(card: richCard)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Timestamp
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .trainer {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Typing Indicator

struct ExampleTypingIndicatorView: View {
    @State private var animationPhase = 0
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.blue.opacity(0.1)))
            
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 8, height: 8)
                        .opacity(animationPhase == index ? 1.0 : 0.3)
                }
            }
            .padding(12)
            .background(Color(.systemGray5))
            .cornerRadius(16)
            
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                animationPhase = (animationPhase + 1) % 3
            }
        }
    }
}

// MARK: - Chat Input Area

struct ChatInputArea: View {
    @Binding var messageText: String
    var isInputFocused: FocusState<Bool>.Binding
    let isGenerating: Bool
    let onSend: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Ask your trainer...", text: $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused(isInputFocused)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(onSend)
                .disabled(isGenerating)
            
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(messageText.isEmpty || isGenerating ? Color.secondary : Color.blue)
            }
            .disabled(messageText.isEmpty || isGenerating)
        }
        .padding()
        .background(.background)
    }
}

// MARK: - Rich Card View

struct ExampleRichCardView: View {
    let card: RichCardData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch card.type {
            case .workoutPlan:
                WorkoutPlanCard(
                    name: card.workoutName ?? "Workout",
                    duration: card.workoutDuration ?? 0,
                    exercises: card.workoutExercises ?? []
                )
            case .dataChart:
                DataChartCard(
                    title: card.chartTitle ?? "Chart",
                    values: card.chartValues ?? [],
                    insight: card.chartInsight ?? "",
                    color: card.chartColor ?? .blue
                )
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

struct WorkoutPlanCard: View {
    let name: String
    let duration: Int
    let exercises: [(name: String, sets: Int, reps: String)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(.orange)
                Text(name)
                    .font(.headline)
                Spacer()
                Text("\(duration) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            ForEach(exercises.indices, id: \.self) { index in
                HStack {
                    Text("\(index + 1).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(exercises[index].name)
                        .font(.subheadline)
                    Spacer()
                    Text("\(exercises[index].sets) × \(exercises[index].reps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct DataChartCard: View {
    let title: String
    let values: [Double]
    let insight: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }
            
            // Simple bar chart
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(values.indices, id: \.self) { index in
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: 20, height: CGFloat(values[index]) / 100 * 80)
                    }
                    .frame(height: 80)
                }
            }
            .padding(.vertical, 8)
            
            Text(insight)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - AI Settings View

struct AISettingsView: View {
    @EnvironmentObject var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("AI Model Status")
                        Spacer()
                        if appStore.aiModelAvailable {
                            Label("Available", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Unavailable", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                } header: {
                    Text("Apple Intelligence")
                } footer: {
                    if appStore.aiModelAvailable {
                        Text("Your trainer uses Apple's on-device language model for personalized, context-aware responses.")
                    } else {
                        Text("Apple Intelligence is not available. Enable it in Settings > Apple Intelligence, or upgrade to a compatible device.")
                    }
                }
                
                Section("Context") {
                    LabeledContent("Readiness", value: "\(appStore.readiness.overall)%")
                    LabeledContent("HRV", value: "\(appStore.dailyMetrics.hrv)ms")
                    LabeledContent("Resting HR", value: "\(appStore.dailyMetrics.restingHR) bpm")
                    LabeledContent("Deep Sleep", value: "\(appStore.dailyMetrics.deepSleep) min")
                }
                
                Section("Coaching Style") {
                    Picker("Style", selection: Binding(
                        get: { appStore.userProfile.coachingStyle },
                        set: { appStore.updateProfile(coachingStyle: $0) }
                    )) {
                        ForEach(CoachingStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                }
                
                Section {
                    Button("Clear Chat History") {
                        appStore.chatMessages.removeAll()
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Quick Action Suggestions View

struct QuickActionSuggestionsView: View {
    @EnvironmentObject var appStore: AppStore
    let onSelect: (String) -> Void
    
    private let suggestions = [
        ("What should I train today?", "dumbbell.fill"),
        ("How's my sleep looking?", "moon.fill"),
        ("Show my progress", "chart.line.uptrend.xyaxis"),
        ("I'm feeling tired", "bed.double.fill"),
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(suggestions, id: \.0) { suggestion in
                    Button {
                        onSelect(suggestion.0)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: suggestion.1)
                                .font(.caption)
                            Text(suggestion.0)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.thinMaterial)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EnhancedChatView()
            .environmentObject(AppStore())
    }
}
