import SwiftUI
import UIKit
import ForgeCore

private enum ForgeLegalConfig {
    static let privacyPolicyURLString = ""
    static var privacyPolicyURL: URL? { URL(string: privacyPolicyURLString) }
}

struct SettingsPageView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL
    @ObservedObject private var health = HealthKitManager.shared

    @State private var showDevicesSheet = false
    @State private var catalogRevision = 0
    @State private var showProfileEditor = false
    @State private var showCoachingStylePicker = false
    @State private var showTrainingThemePicker = false
    @State private var showNutritionTargetsEditor = false
    @State private var showTermsSheet = false
    @State private var showClinicalData = false
    @State private var showDataPermissions = false
    @State private var showGoalsEditor = false
    @State private var showScheduleEditor = false
    @State private var showEquipmentPicker = false
    @State private var showWorkoutsEditor = false
    @State private var showBackendURL = false
    @State private var showShareSheet = false
    @State private var showAbout = false
    @State private var showLocalPrivacy = false
    @State private var confirmSignOut = false
    @State private var backendURLDraft = AriaService.shared.baseURL.absoluteString
    @State private var briefSettings: BriefNotificationSettings
    @ObservedObject private var weeklyReview = WeeklyAriaReviewStore.shared

    let dayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    init() {
        _briefSettings = State(initialValue: ForgePersistence.loadBriefNotificationSettings())
    }

    var scheduleDays: String {
        store.userProfile.weeklySchedule.map { dayLabels[$0] }.joined(separator: " / ")
    }

    // Mirrors NutritionTargetsEditorView.load()'s own useCustom check.
    var nutritionTargetsAreCustom: Bool {
        let prefs = store.nutritionPreferences
        return prefs.proteinGrams != nil || prefs.calorieTarget != nil
            || prefs.stepTarget != nil || prefs.waterGlassesTarget != nil
            || prefs.hydrationTargetMl != nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // World-class identity hero — avatar, signature stats, readiness, actions.
                ProfileHeroHeader(
                    onEdit: { showProfileEditor = true },
                    onShare: { showShareSheet = true }
                )
                .padding(.top, 8)
                .padding(.bottom, FDS.Spacing.sm)

                sectionHeader("ARIA")
                SectionCard {
                    Button(action: { showCoachingStylePicker = true }) {
                        SettingsRow(icon: "person.fill", iconColor: .ember, label: "Coaching Style",
                                    trailingText: store.userProfile.coachingStyle.label, showChevron: true)
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.borderColor)
                    Button(action: { showTrainingThemePicker = true }) {
                        SettingsRow(
                            icon: store.userProfile.trainingTheme.icon,
                            iconColor: Color(hex: store.userProfile.trainingTheme.accentHex),
                            label: "Training Theme",
                            trailingText: store.userProfile.trainingTheme.label,
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().background(Color.borderColor)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Personal coaches")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.textPrimary)
                        Text("ARIA spawns as many specialists as the question needs — one live call, the rest in parallel on this phone. Pin one to lead, or leave Auto.")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                        Button {
                            store.replayAriaUseOnboarding()
                        } label: {
                            Text("Meet ARIA again")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.ember)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                        FlowLayout(spacing: 8) {
                            coachPinChip(nil, title: "Auto")
                            // Same roster as the chat pin row: the five
                            // tracked modes plus Cycle, not .allCases (which
                            // would also offer a redundant direct pin to
                            // .aria -- "Auto" already covers that).
                            ForEach(AriaCoachAgent.trackedModes + [.cycle]) { agent in
                                if AriaCoachAgentRouter.isAvailable(
                                    agent,
                                    context: AriaCoachAgentRouter.context(pinned: store.pinnedCoachAgent)
                                ) {
                                    coachPinChip(agent, title: agent.label)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider().background(Color.borderColor)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.userProfile.coachingStyle.description)
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                            .lineSpacing(2)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                        Divider().background(Color.borderColor)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Training Goals")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.textPrimary)
                            FlowLayout(spacing: 8) {
                                ForEach(store.userProfile.fitnessGoals) { goal in
                                    Text(goal.label)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.ember)
                                        .padding(.horizontal, 12).padding(.vertical, 5)
                                        .background(Color.ember.opacity(0.12))
                                        .cornerRadius(100)
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                }

                // Connected Devices
                sectionHeader("Connected Devices")
                SectionCard {
                    Color.clear.frame(width: 0, height: 0).hidden().id(catalogRevision)
                    if store.userProfile.connectedDevices.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "link.badge.plus")
                                .font(.system(size: 16))
                                .foregroundColor(.textTertiary)
                            Text("No devices yet. Browse the library — LARQ, Oura, Garmin, Watch and more.")
                                .font(.system(size: 14))
                                .foregroundColor(.textSecondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    } else {
                        ForEach(Array(HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices).enumerated()), id: \.element) { idx, raw in
                            if idx > 0 { Divider().background(Color.borderColor) }
                            let device = HealthDeviceCatalog.device(matching: raw)
                            Button { showDevicesSheet = true } label: {
                                SettingsRow(
                                    icon: device?.symbolName ?? "sensor.tag.radiowaves.forward",
                                    iconColor: .steel,
                                    label: device?.name ?? raw,
                                    showChevron: true
                                ) {
                                    if let device {
                                        DeviceProductImage(device: device, size: 28, cornerRadius: 6)
                                    }
                                    HStack(spacing: 5) {
                                        Circle().fill(Color.success).frame(width: 8, height: 8)
                                        Text(device?.writesToAppleHealth == true ? "Health" : "iOS")
                                            .font(.system(size: 12))
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Divider().background(Color.borderColor)
                    Button { showDevicesSheet = true } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().stroke(Color.borderLight, style: StrokeStyle(lineWidth: 1, dash: [4])).frame(width: 32, height: 32)
                                Image(systemName: "plus").font(.system(size: 13)).foregroundColor(.textTertiary)
                            }
                            Text("Browse compatible devices")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.ember)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                // Account
                sectionHeader("Account")
                SectionCard {
                    SettingsRow(
                        icon: "person.crop.circle.fill",
                        iconColor: .ember,
                        label: store.authEmail.isEmpty ? "Signed in" : store.authEmail,
                        trailingText: store.authProvider.isEmpty ? "Session" : store.authProvider.capitalized
                    )
                    Divider().background(Color.borderColor)
                    SettingsRow(
                        icon: "checkmark.shield.fill",
                        iconColor: .success,
                        label: "Session",
                        trailingText: store.isAuthenticated ? "Active" : "None"
                    )
                }

                // Health
                sectionHeader("Apple Health")
                SectionCard {
                    SettingsRow(
                        icon: "heart.text.square.fill",
                        iconColor: store.healthKitLive ? .success : .warning,
                        label: "Apple Health",
                        trailingText: store.healthKitLive ? "Connected" : "Offline"
                    )
                    Divider().background(Color.borderColor)
                    Button {
                        Task {
                            await store.reconnectHealthKit()
                            FDS.notificationHaptic(store.healthKitLive ? .success : .warning)
                        }
                    } label: {
                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: .ember,
                            label: store.healthKitLive ? "Resync Apple Health" : "Reconnect Apple Health",
                            trailingText: "Now",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    SettingsRow(
                        icon: "calendar.badge.clock",
                        iconColor: .steel,
                        label: "Cycle quiet sync",
                        trailingText: "Weekly"
                    )
                }

                // Cycle privacy (Home opens the full Cycle surface)
                sectionHeader("Cycle privacy")
                SectionCard {
                    SettingsRow(
                        icon: "lock.shield.fill",
                        iconColor: Color(hex: "22C55E"),
                        label: "Coaching-only data",
                        trailingText: MenstrualHealthStore.shared.settings.enabled ? "On" : "Off"
                    )
                    Divider().background(Color.borderColor)
                    SettingsRow(
                        icon: "chart.line.uptrend.xyaxis",
                        iconColor: .ember,
                        label: "Prediction accuracy",
                        trailingText: {
                            if let mae = MenstrualHealthStore.shared.accuracyReport.maeDays {
                                return String(format: "MAE %.1fd", mae)
                            }
                            return "Learning"
                        }()
                    )
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "scope", iconColor: Color(hex: "A855F7"), label: "High-accuracy mode") {
                        ForgeToggle(isOn: Binding(
                            get: { MenstrualHealthStore.shared.settings.highAccuracyMode },
                            set: { v in MenstrualHealthStore.shared.updateSettings { $0.highAccuracyMode = v } }
                        ))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "eye.fill", iconColor: .ember, label: "Share cycle with ARIA") {
                        ForgeToggle(isOn: Binding(
                            get: { MenstrualHealthStore.shared.settings.shareWithAria },
                            set: { v in MenstrualHealthStore.shared.updateSettings { $0.shareWithAria = v } }
                        ))
                    }
                    Divider().background(Color.borderColor)
                    Button {
                        store.openCycleHealth(pane: "me")
                    } label: {
                        SettingsRow(
                            icon: "house.fill",
                            iconColor: Color(hex: "EF4444"),
                            label: "Open Cycle Health",
                            trailingText: "Home",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Data & Privacy
                sectionHeader("Data & Privacy")
                SectionCard {
                    Button { showDataPermissions = true } label: {
                        SettingsRow(icon: "lock.shield.fill", iconColor: .steel, label: "ARIA Data Permissions",
                                    trailingText: "Manage", showChevron: true)
                    }
                    .buttonStyle(.plain)
                }

                // Focus / quiet
                sectionHeader("Focus")
                SectionCard {
                    SettingsRow(icon: "moon.fill", iconColor: .steel, label: "Quiet mode") {
                        ForgeToggle(isOn: Binding(
                            get: { store.quietMode },
                            set: { store.setQuietMode($0) }
                        ))
                    }
                }

                // Workout Preferences
                sectionHeader("Workout Preferences")
                SectionCard {
                    Button { showGoalsEditor = true } label: {
                        SettingsRow(
                            icon: "target",
                            iconColor: .ember,
                            label: "Training Goals",
                            trailingText: "\(store.userProfile.fitnessGoals.count)",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showWorkoutsEditor = true } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Preferred Types").font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                            if store.userProfile.preferredWorkouts.isEmpty {
                                Text("Tap to choose the sessions you actually do.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                            } else {
                                FlowLayout(spacing: 8) {
                                    ForEach(store.userProfile.preferredWorkouts) { type in
                                        Text(type.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.textSecondary)
                                            .padding(.horizontal, 12).padding(.vertical, 5)
                                            .background(Color.surfaceElevated)
                                            .cornerRadius(100)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showScheduleEditor = true } label: {
                        SettingsRow(icon: "dumbbell.fill", iconColor: .ember, label: "Training Schedule",
                                    trailingText: scheduleDays.isEmpty ? "Set days" : scheduleDays, showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showEquipmentPicker = true } label: {
                        SettingsRow(
                            icon: store.userProfile.trainingEquipment.icon,
                            iconColor: .steel,
                            label: "Equipment",
                            trailingText: store.userProfile.trainingEquipment.rawValue,
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Nutrition
                sectionHeader("Nutrition")
                SectionCard {
                    Button { showNutritionTargetsEditor = true } label: {
                        SettingsRow(
                            icon: "fork.knife",
                            iconColor: .ember,
                            label: "Nutrition Targets",
                            trailingText: nutritionTargetsAreCustom ? "Custom" : "Recommended",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Notifications
                sectionHeader("Notifications")
                SectionCard {
                    SettingsRow(icon: "bell.fill", iconColor: .ember, label: "Workout Reminders") {
                        ForgeToggle(isOn: notificationBinding(\.workoutReminders))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .steel, label: "ARIA Proactive Briefs") {
                        ForgeToggle(isOn: Binding(
                            get: { store.briefNotificationsEnabled },
                            set: { store.setBriefNotificationsEnabled($0) }
                        ))
                    }
                    if store.briefNotificationsEnabled {
                        Divider().background(Color.borderColor)
                        briefTimeRow(
                            icon: "sunrise.fill",
                            iconColor: Color(hex: "F59E0B"),
                            label: "Morning brief",
                            hour: $briefSettings.morningHour,
                            minute: $briefSettings.morningMinute
                        )
                        Divider().background(Color.borderColor)
                        briefTimeRow(
                            icon: "sunset.fill",
                            iconColor: Color(hex: "6366F1"),
                            label: "Evening brief",
                            hour: $briefSettings.eveningHour,
                            minute: $briefSettings.eveningMinute
                        )
                    }
                    Divider().background(Color.borderColor)
                    Button {
                        weeklyReview.showSheet = true
                    } label: {
                        SettingsRow(
                            icon: "calendar.badge.clock",
                            iconColor: .ember,
                            label: "Weekly ARIA evaluation",
                            trailingText: weeklyReview.isDue ? "Due" : "Done",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .success, label: "Recovery Alerts") {
                        ForgeToggle(isOn: notificationBinding(\.recoveryAlerts))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "bell.fill", iconColor: .textSecondary, label: "Weekly Summary") {
                        ForgeToggle(isOn: notificationBinding(\.weeklySummary))
                    }
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "drop.fill", iconColor: Color(hex: "38BDF8"), label: "Lifestyle Reminders") {
                        ForgeToggle(isOn: notificationBinding(\.lifestyleReminders))
                    }
                }

                sectionHeader("Clinical Data (Non PHI)")
                Button { showClinicalData = true } label: {
                    SettingsRow(
                        icon: "pills.fill",
                        iconColor: .ember,
                        label: "Allergies, meds, labs",
                        trailingText: clinicalTrailingText,
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)
                .background(Color.surface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor, lineWidth: 1))

                // More
                sectionHeader("More")
                SectionCard {
                    Button { showDataPermissions = true } label: {
                        SettingsRow(icon: "lock.shield.fill", iconColor: .textSecondary, label: "Data & Privacy",
                                    trailingText: "Apple Health + ARIA", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button {
                        if let privacyPolicyURL = ForgeLegalConfig.privacyPolicyURL {
                            openURL(privacyPolicyURL)
                        } else {
                            showLocalPrivacy = true
                        }
                    } label: {
                        SettingsRow(icon: "doc.text.fill", iconColor: .textSecondary, label: "Privacy Policy",
                                    trailingText: ForgeLegalConfig.privacyPolicyURL == nil ? "Required" : nil,
                                    showChevron: ForgeLegalConfig.privacyPolicyURL != nil)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showTermsSheet = true } label: {
                        SettingsRow(icon: "doc.plaintext.fill", iconColor: .textSecondary, label: "Terms & Conditions",
                                    trailingText: "Local-first", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    SettingsRow(icon: "creditcard.fill", iconColor: .textSecondary, label: "Subscription",
                                trailingText: "Coming soon")
                    Divider().background(Color.borderColor)
                    // Was a flat label showing an address you couldn't tap. Now it opens
                    // a pre-addressed mail draft with the diagnostics a support reply needs.
                    Button {
                        openSupportEmail()
                    } label: {
                        SettingsRow(icon: "questionmark.circle.fill", iconColor: .textSecondary,
                                    label: "Help & Support", trailingText: "Email us", showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showAbout = true } label: {
                        SettingsRow(icon: "info.circle.fill", iconColor: .textSecondary, label: "About Forge",
                                    trailingText: ForgeAppInfo.shortVersion, showChevron: true)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Color.borderColor)
                    Button { showBackendURL = true } label: {
                        SettingsRow(
                            icon: "server.rack",
                            iconColor: .steel,
                            label: "ARIA backend URL",
                            trailingText: "Bedrock",
                            showChevron: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                sectionHeader("All pages")
                Text("The rooms. Open one when you need to log or override — ARIA already reads them.")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .padding(.bottom, 10)
                ForgeExploreDestinationsGrid()
                    .padding(.bottom, FDS.Spacing.md)

                // Log Out
                Button {
                    confirmSignOut = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16))
                        Text("Log Out").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.surface)
                    .cornerRadius(14)
                }
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $showProfileEditor) {
            ProfileEditorView()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareProgressView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showCoachingStylePicker) {
            CoachingStylePickerView()
        }
        .sheet(isPresented: $showTrainingThemePicker) {
            TrainingThemePickerView()
        }
        .sheet(isPresented: $showNutritionTargetsEditor) {
            NutritionTargetsEditorView()
        }
        .sheet(isPresented: $showDevicesSheet) {
            ConnectedDevicesLibraryView()
                .environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthDeviceCatalogDidChange)) { _ in
            catalogRevision += 1
        }
        .sheet(isPresented: $showLocalPrivacy) {
            NavigationStack {
                ScrollView {
                    Text("Forge keeps Apple Health data on this device. ARIA only receives what you allow under Data Permissions. Wearables on the Devices list write to Apple Health through their own iOS apps — Forge reads that ledger, it does not scrape vendor accounts.")
                        .font(.system(size: 15))
                        .foregroundColor(.textSecondary)
                        .padding(20)
                }
                .background(Color.background)
                .navigationTitle("Privacy")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showLocalPrivacy = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showTermsSheet) {
            ForgeTermsAndConditionsView()
        }
        .sheet(isPresented: $showAbout) {
            ForgeAboutView()
        }
        .sheet(isPresented: $showClinicalData) {
            ClinicalDataNonPHIView()
        }
        .sheet(isPresented: $showDataPermissions) {
            DataPermissionsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showGoalsEditor) {
            FitnessGoalsEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showScheduleEditor) {
            TrainingScheduleEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showEquipmentPicker) {
            EquipmentPickerView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showWorkoutsEditor) {
            PreferredWorkoutsEditorView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showBackendURL) {
            NavigationStack {
                Form {
                    Section("Backend (Bedrock path)") {
                        TextField("https://…", text: $backendURLDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                    Section {
                        Button("Save") {
                            AriaService.shared.setBaseURL(backendURLDraft)
                            showBackendURL = false
                        }
                    }
                }
                .navigationTitle("ARIA backend")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showBackendURL = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .confirmationDialog("Log out of Forge?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { store.signOut() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll need to sign in again. Health data stays on this iPhone.")
        }
        .onChange(of: briefSettings) { _, updated in
            ForgePersistence.saveBriefNotificationSettings(updated)
            store.updateBriefNotificationSchedule(
                morningHour: updated.morningHour,
                morningMinute: updated.morningMinute,
                eveningHour: updated.eveningHour,
                eveningMinute: updated.eveningMinute
            )
        }
        .onAppear { weeklyReview.refreshDue() }
    }

    private func coachPinChip(_ agent: AriaCoachAgent?, title: String) -> some View {
        let selected = store.pinnedCoachAgent == agent
        return Button {
            store.pinnedCoachAgent = agent
            if let agent { store.lastRoutedCoachAgent = agent }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selected ? .ember : .textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(selected ? Color.ember.opacity(0.18) : Color.ember.opacity(0.12))
                .cornerRadius(100)
        }
        .buttonStyle(.plain)
    }

    /// Opens the user's mail client with a support draft already addressed and stamped
    /// with build info, so a bug report arrives with the context we'd otherwise ask for.
    private func openSupportEmail() {
        let subject = "Forge support request"
        let body = """


        ---
        App: Forge \(ForgeAppInfo.fullVersion)
        Device: \(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = ForgeAppInfo.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        if let url = components.url {
            openURL(url)
        }
    }

    private var clinicalTrailingText: String {
        if let summary = health.clinicalSummary, summary.hasData {
            return "\(summary.totalRecordCount)"
        }
        return health.hasStructuredRecordsAccess ? "Open" : "Connect"
    }

    private func notificationBinding(_ keyPath: WritableKeyPath<AppNotificationSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.notificationSettings[keyPath: keyPath] },
            set: { newValue in
                var settings = store.notificationSettings
                settings[keyPath: keyPath] = newValue
                store.updateNotificationSettings(settings)
            }
        )
    }

    private func briefTimeRow(
        icon: String,
        iconColor: Color,
        label: String,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        SettingsRow(icon: icon, iconColor: iconColor, label: label) {
            DatePicker(
                label,
                selection: Binding(
                    get: { Self.clockDate(hour: hour.wrappedValue, minute: minute.wrappedValue) },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        hour.wrappedValue = min(23, max(0, parts.hour ?? 0))
                        minute.wrappedValue = min(59, max(0, parts.minute ?? 0))
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(.ember)
            .accessibilityLabel(label)
        }
    }

    /// Fixed calendar day so DST cannot flip 6:00 into 5:00 when the picker
    /// is bound to "today".
    private static func clockDate(hour: Int, minute: Int) -> Date {
        var parts = DateComponents()
        parts.calendar = Calendar.current
        parts.year = 2026
        parts.month = 1
        parts.day = 15
        parts.hour = min(23, max(0, hour))
        parts.minute = min(59, max(0, minute))
        return parts.date ?? Date()
    }

    func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.textTertiary)
            .tracking(1)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }
}
