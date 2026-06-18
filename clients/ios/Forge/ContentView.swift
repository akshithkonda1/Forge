import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.isOnboarded {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var voiceModeActive = false
    @State private var previousTab: AppTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch store.activeTab {
                case .home: HomeView()
                case .chat: ChatView()
                case .workout: WorkoutView()
                case .sleep: SleepView()
                case .profile: ProfileTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 72)
            .transition(tabTransition(for: store.activeTab))
            .id(store.activeTab)

            ForgeTabBar(voiceModeActive: $voiceModeActive)
        }
        .background(Color.forgeBackground)
        .ignoresSafeArea(.keyboard)
        .overlay {
            if voiceModeActive {
                VoiceOrbOverlay(
                    mood: ARIAMood.derive(readiness: store.readiness.overall),
                    isShowing: $voiceModeActive
                ) { text in
                    store.sendUserMessage(text)
                }
            }
        }
        .onChange(of: store.activeTab) { oldTab, _ in
            previousTab = oldTab
        }
    }

    private func tabTransition(for tab: AppTab) -> AnyTransition {
        switch tab {
        case .chat:
            return .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97)),
                removal: .opacity
            )
        case .workout:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .opacity
            )
        default:
            return .opacity.animation(.easeOut(duration: 0.22))
        }
    }
}

struct ForgeTabBar: View {
    @EnvironmentObject var store: AppStore
    @Binding var voiceModeActive: Bool

    private let tabs: [(tab: AppTab, icon: String, label: String)] = [
        (.home, "house.fill", "Home"),
        (.workout, "dumbbell.fill", "Workout"),
        (.chat, "message.fill", "ARIA"),
        (.sleep, "moon.fill", "Sleep"),
        (.profile, "person.fill", "Profile"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, item in
                if index == 2 {
                    ariaTabButton
                } else {
                    tabButton(item)
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            Color.forgeBackground.opacity(0.8)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color.forgeBorder),
            alignment: .top
        )
    }

    private var ariaTabButton: some View {
        Button {
            withAnimation(FDS.Spring.page) { store.activeTab = .chat }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(Color.ember)
                        .frame(width: 52, height: 52)
                        .shadow(color: .ember.opacity(0.45), radius: 12, y: 4)

                    AuroraOrbView(state: .idle, amplitude: 0.1, mood: .focused, size: 36)
                }
                .offset(y: -10)

                Text("ARIA")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(store.activeTab == .chat ? .ember : .textTertiary)
                    .offset(y: -8)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .forgePress()
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                voiceModeActive = true
                store.activeTab = .chat
            }
        )
    }

    private func tabButton(_ item: (tab: AppTab, icon: String, label: String)) -> some View {
        Button {
            withAnimation(FDS.Spring.page) { store.activeTab = item.tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 20))
                    .foregroundColor(store.activeTab == item.tab ? .ember : .textTertiary)

                Text(item.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(store.activeTab == item.tab ? .ember : .textTertiary)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .forgePress()
    }
}

struct VoiceOrbOverlay: View {
    let mood: ARIAMood
    @Binding var isShowing: Bool
    let onRecognized: (String) -> Void

    @State private var orbState: AROrbState = .listening
    @State private var amplitude: Double = 0.35
    @State private var listenTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                AuroraOrbView(state: orbState, amplitude: amplitude, mood: mood, size: 220)

                Text(orbState == .processing ? "Processing…" : "Listening…")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Button("Cancel") {
                    listenTask?.cancel()
                    isShowing = false
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textSecondary)
                .padding(.bottom, 40)
            }
        }
        .onAppear { startListening() }
        .onDisappear {
            listenTask?.cancel()
            listenTask = nil
        }
    }

    private func startListening() {
        listenTask?.cancel()
        listenTask = Task {
            orbState = .listening
            for _ in 0..<12 {
                try? await Task.sleep(nanoseconds: 120_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    amplitude = Double.random(in: 0.2...0.85)
                }
            }
            if Task.isCancelled { return }
            await MainActor.run {
                orbState = .processing
                amplitude = 0.5
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                onRecognized("How should I train today?")
                isShowing = false
            }
        }
    }
}