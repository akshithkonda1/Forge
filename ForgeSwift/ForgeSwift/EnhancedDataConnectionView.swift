import SwiftUI

// MARK: - Enhanced Device & Data Connection View

struct EnhancedDataConnectionView: View {
    let onNext: () -> Void
    @EnvironmentObject var store: AppStore
    @StateObject private var dataManager = OnboardingDataManager.shared
    @State private var appeared = false
    @State private var showHealthKitSheet = false
    @State private var isConnectingAll = false
    @State private var completedStep = 0
    
    var allConnected: Bool {
        dataManager.healthKitAuthorized && 
        dataManager.calendarAuthorized && 
        dataManager.notificationsAuthorized
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Connect Your Data")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    if isConnectingAll {
                        ProgressView()
                            .tint(.ember)
                    }
                }
                
                Text("FORGE uses your device data to create the perfect training plan — personalized to your schedule, fitness level, and recovery.")
                    .font(.system(size: 15))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 28)

            // Connection progress
            if allConnected {
                ConnectionSuccessBanner(recommendations: dataManager.generatePersonalizedRecommendations())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // HealthKit - Primary
                    DataSourceCard(
                        icon: "heart.text.square.fill",
                        title: "Health & Fitness",
                        description: "Heart rate, workouts, sleep, and activity data",
                        isConnected: dataManager.healthKitAuthorized,
                        isRequired: true,
                        priority: 1
                    ) {
                        connectHealthKit()
                    }
                    
                    // Show health snapshot if connected
                    if dataManager.healthKitAuthorized, let snapshot = dataManager.healthSnapshot {
                        HealthDataPreviewCard(snapshot: snapshot)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    
                    // Calendar
                    DataSourceCard(
                        icon: "calendar",
                        title: "Calendar Access",
                        description: "Smart workout scheduling around your commitments",
                        isConnected: dataManager.calendarAuthorized,
                        isRequired: false,
                        priority: 2
                    ) {
                        connectCalendar()
                    }
                    
                    // Show suggested workout times if calendar connected
                    if dataManager.calendarAuthorized && !dataManager.suggestedWorkoutTimes.isEmpty {
                        WorkoutTimeSlotsCard(slots: dataManager.suggestedWorkoutTimes)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                    
                    // Notifications
                    DataSourceCard(
                        icon: "bell.badge.fill",
                        title: "Workout Reminders",
                        description: "Never miss a training session with smart notifications",
                        isConnected: dataManager.notificationsAuthorized,
                        isRequired: false,
                        priority: 3
                    ) {
                        connectNotifications()
                    }
                    
                    // Contacts (optional)
                    DataSourceCard(
                        icon: "person.2.fill",
                        title: "Find Workout Buddies",
                        description: "Invite friends and train together",
                        isConnected: dataManager.contactsAuthorized,
                        isRequired: false,
                        priority: 4
                    ) {
                        connectContacts()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            // Quick connect all button
            if !allConnected {
                Button {
                    connectAll()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Connect All")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(
                            colors: [Color.ember, Color(hex: "FF5A00")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                    .shadow(color: Color.ember.opacity(0.4), radius: 14, y: 5)
                }
                .disabled(isConnectingAll)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            // Continue button
            Button(action: onNext) {
                HStack(spacing: 8) {
                    Text(allConnected ? "Continue with Smart Setup" : "Skip for Now")
                        .font(.system(size: 17, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(allConnected ? .white : .textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(allConnected ? AnyShapeStyle(LinearGradient.emberGradient) : AnyShapeStyle(Color.surface))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(allConnected ? Color.clear : Color.borderColor, lineWidth: 1)
                )
                .shadow(color: allConnected ? Color.ember.opacity(0.4) : .clear, radius: 14, y: 5)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .background(Color.background.ignoresSafeArea())
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: dataManager.healthKitAuthorized)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: dataManager.calendarAuthorized)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: allConnected)
    }
    
    // MARK: - Connection Actions
    
    private func connectAll() {
        guard !isConnectingAll else { return }
        isConnectingAll = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        Task {
            await dataManager.requestAllPermissions()
            await MainActor.run {
                isConnectingAll = false
                if allConnected {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }
    
    private func connectHealthKit() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let granted = await dataManager.requestHealthKitPermission()
            if granted {
                await dataManager.fetchHealthData()
            }
        }
    }
    
    private func connectCalendar() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let granted = await dataManager.requestCalendarPermission()
            if granted {
                await dataManager.analyzeCalendarForWorkoutSlots()
            }
        }
    }
    
    private func connectNotifications() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let granted = await dataManager.requestNotificationPermission()
            if granted {
                await dataManager.scheduleInitialWorkoutReminders()
            }
        }
    }
    
    private func connectContacts() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task {
            let granted = await dataManager.requestContactsPermission()
            if granted {
                await dataManager.findFitnessContacts()
            }
        }
    }
}

// MARK: - Data Source Card

struct DataSourceCard: View {
    let icon: String
    let title: String
    let description: String
    let isConnected: Bool
    let isRequired: Bool
    let priority: Int
    let action: () -> Void
    
    @State private var appeared = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isConnected ? Color.success.opacity(0.12) : Color.ember.opacity(0.08))
                    .frame(width: 60, height: 60)
                
                Image(systemName: isConnected ? "checkmark.seal.fill" : icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(isConnected ? .success : .ember)
                    .symbolEffect(.bounce, value: isConnected)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    if isRequired {
                        Text("Required")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.ember)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.ember.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Action button
            if !isConnected {
                Button(action: action) {
                    Text("Connect")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.ember)
                        .cornerRadius(8)
                }
                .accessibilityLabel("Connect \(title)")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.success)
                    .accessibilityLabel("\(title) connected")
            }
        }
        .accessibilityElement(children: .combine)
        .padding(16)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isConnected ? Color.success.opacity(0.4) : Color.borderColor.opacity(0.3),
                    lineWidth: isConnected ? 2 : 1
                )
        )
        .shadow(
            color: isConnected ? Color.success.opacity(0.1) : .black.opacity(0.04),
            radius: isConnected ? 12 : 6,
            y: 3
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(Double(priority) * 0.08)) {
                appeared = true
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isConnected)
    }
}

// MARK: - Connection Success Banner

struct ConnectionSuccessBanner: View {
    let recommendations: OnboardingRecommendations
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.success)
                
                Text("All Systems Connected")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.success)
                
                Spacer()
                
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundColor(.ember)
                    .symbolEffect(.pulse)
            }
            
            if recommendations.hasRecommendations {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Smart Insights:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    if let advice = recommendations.workoutIntensityAdvice {
                        InsightRow(icon: "bolt.fill", text: advice, color: .ember)
                    }
                    if let advice = recommendations.scheduleAdvice {
                        InsightRow(icon: "calendar", text: advice, color: .blue)
                    }
                }
            }
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.success.opacity(0.08))
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [Color.success.opacity(0.4), Color.success.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3)) {
                appeared = true
            }
        }
    }
}

struct InsightRow: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
        }
    }
}

// MARK: - Workout Time Slots Card

struct WorkoutTimeSlotsCard: View {
    let slots: [WorkoutTimeSlot]
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                Text("Suggested Workout Times")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("Based on your calendar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
            
            VStack(spacing: 8) {
                ForEach(slots.prefix(3)) { slot in
                    WorkoutTimeSlotRow(slot: slot)
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(0.04))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.95)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2)) {
                appeared = true
            }
        }
    }
}

struct WorkoutTimeSlotRow: View {
    let slot: WorkoutTimeSlot
    
    var qualityColor: Color {
        switch slot.quality {
        case .optimal: return .success
        case .good: return .ember
        case .acceptable: return .steel
        }
    }
    
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.dayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(slot.formattedTimeRange)
                    .font(.system(size: 11))
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(qualityColor)
                    .frame(width: 6, height: 6)
                Text(slot.quality.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(qualityColor)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(qualityColor.opacity(0.1))
            .cornerRadius(6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.surface.opacity(0.5))
        .cornerRadius(10)
    }
}
