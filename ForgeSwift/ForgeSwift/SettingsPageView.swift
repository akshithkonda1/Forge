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
    @State private var showStandBySheet = false
    @State private var catalogRevision = 0
    @State private var showWhatIKnow = false
    @State private var showProfileEditor = false
    @State private var showCoachingStylePicker = false
    @State private var showTrainingThemePicker = false
    @State private var showNutritionTargetsEditor = false
    @State private var showTermsSheet = false
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
    // The Cycle controls read this store directly; observing it keeps them in step with changes.
    @ObservedObject private var cycleStore = MenstrualHealthStore.shared

    let dayLabels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

    init() {
        _briefSettings = State(initialValue: ForgePersistence.loadBriefNotificationSettings())
    }

    var scheduleDays: String {
        let split = store.userProfile.weeklySplit
        if split.isEmpty {
            return store.userProfile.weeklySchedule.map { dayLabels[$0] }.joined(separator: " / ")
        }
        return WeeklySplit.summary(mode: store.userProfile.schedulePlanningMode, split: split)
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
                // Identity hero: avatar, signature stats, readiness, actions.
                ProfileHeroHeader(
                    onEdit: { showProfileEditor = true },
                    onShare: { showShareSheet = true }
                )

                allPagesGroup
                ariaGroup
                workoutGroup
                nutritionGroup

                PeopleSettingsSection()

                // Life Context: Reminders and shared conversations, off by default.
                LifeContextSettingsSection()

                devicesGroup
                appleHealthGroup
                clinicalGroup
                cyclePrivacyGroup
                cycleGroup
                notificationsGroup
                dataPrivacyGroup
                accountGroup
                moreGroup
                logOutButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .forgeScreenInsets(top: ForgeLayout.screenTop, bottom: ForgeLayout.scrollBottomClearance)
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
        .sheet(isPresented: $showWhatIKnow) {
            NavigationStack {
                WhatIKnowView()
            }
        }
        .sheet(isPresented: $showTrainingThemePicker) {
            TrainingThemePickerView()
        }
        .sheet(isPresented: $showNutritionTargetsEditor) {
            NutritionTargetsEditorView()
        }
        .sheet(isPresented: $showStandBySheet) {
            StandByCustomizationView()
        }
        .sheet(isPresented: $showDevicesSheet) {
            ConnectedDevicesLibraryView()
                .environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .healthDeviceCatalogDidChange)) { _ in
            catalogRevision += 1
        }
        .sheet(isPresented: $showLocalPrivacy) {
            localPrivacySheet
        }
        .sheet(isPresented: $showTermsSheet) {
            ForgeTermsAndConditionsView()
        }
        .sheet(isPresented: $showAbout) {
            ForgeAboutView()
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
            backendURLSheet
        }
        .confirmationDialog("Log out of Forge?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                FDS.haptic(.destructive)
                store.signOut()
            }
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

    // MARK: - Sheets

    private var localPrivacySheet: some View {
        NavigationStack {
            ScrollView {
                Text("Forge keeps Apple Health data on this device — including Oura, Garmin, Watch, and any other wearable that writes to Apple Health. ARIA reads that ledger here and gives an opinion. Claude and Grok never receive the sample warehouse. Forge account storage is the user record, not your chart.")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .forgeScreenInsets(top: FDS.Spacing.lg)
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

    private var backendURLSheet: some View {
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
            .scrollContentBackground(.hidden)
            .background(Color.background)
            .navigationTitle("ARIA backend")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { showBackendURL = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Groups

    private var allPagesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                "All pages",
                subtitle: "The rooms. Open one when you need to log or override — ARIA already reads them."
            )
            ForgeExploreDestinationsGrid()
        }
    }

    private var ariaGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("ARIA")
            SectionCard {
                settingsLink(
                    icon: "folder.fill",
                    iconColor: .ember,
                    label: "ARIA memory & voice",
                    footnote: "Notes, persona, tone, check-ins"
                ) { showWhatIKnow = true }

                SettingsHairline()
                settingsLink(
                    icon: "person.fill",
                    iconColor: .ember,
                    label: "Coaching Style",
                    trailingText: store.userProfile.coachingStyle.label,
                    footnote: store.userProfile.coachingStyle.description
                ) { showCoachingStylePicker = true }

                SettingsHairline()
                settingsLink(
                    icon: store.userProfile.trainingTheme.icon,
                    iconColor: Color(hex: store.userProfile.trainingTheme.accentHex),
                    label: "Training Theme",
                    trailingText: store.userProfile.trainingTheme.label
                ) { showTrainingThemePicker = true }

                SettingsHairline()
                leadCoachBlock

                SettingsHairline()
                settingsLink(
                    icon: "text.bubble",
                    iconColor: .aurora,
                    label: "Meet ARIA again",
                    hint: "Replays the ARIA introduction"
                ) { store.replayAriaUseOnboarding() }

                trainingGoalsBlock
            }
        }
    }

    /// Lead coach: a standard row, its explanation, then the pin chips at the row inset.
    private var leadCoachBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                icon: "person.2.fill",
                iconColor: .ember,
                label: "Lead coach",
                trailingText: store.pinnedCoachAgent?.label ?? "Auto"
            )
            .accessibilityElement(children: .combine)

            rowFootnote(
                "ARIA spawns as many specialists as the question needs — one live call, the rest in parallel on this phone. Pin one to lead, or leave Auto."
            )

            debugCoachModeBlock

            ForgeFlowLayout(spacing: ForgeLayout.chipGap, lineSpacing: ForgeLayout.interactiveChipLineGap) {
                coachPinChip(nil, title: "Auto")
                // Same roster as the chat pin row: the five tracked modes plus
                // Cycle, not .allCases (which would also offer a redundant
                // direct pin to .aria -- "Auto" already covers that).
                ForEach(AriaCoachAgent.trackedModes + [.cycle]) { agent in
                    if AriaCoachAgentRouter.isAvailable(
                        agent,
                        context: AriaCoachAgentRouter.context(pinned: store.pinnedCoachAgent)
                    ) {
                        coachPinChip(agent, title: agent.label)
                    }
                }
            }
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.bottom, ForgeLayout.rowGap)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var debugCoachModeBlock: some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: FDS.Spacing.sm) {
            Text("ARIA coach mode")
                .font(HomeType.label)
                .foregroundStyle(Color.textSecondary)
            Text(AriaOperatingMode.current.badge)
                .font(HomeType.micro)
                .foregroundStyle(Color.textSecondary)
            ForEach(AriaOperatingMode.selectableCases) { mode in
                Button {
                    AriaOperatingMode.setOverride(mode)
                } label: {
                    HStack {
                        Text(mode.settingsLabel)
                            .font(HomeType.body)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if AriaOperatingMode.current == mode {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.paper)
                        }
                    }
                    .frame(minHeight: ForgeUX.minTap)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button("Reset to auto") {
                AriaOperatingMode.setOverride(nil)
            }
            .font(HomeType.label)
            .foregroundStyle(Color.textSecondary)
            .frame(minHeight: ForgeUX.minTap)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.bottom, FDS.Spacing.md)
        #endif
    }

    @ViewBuilder
    private var trainingGoalsBlock: some View {
        let goals = store.userProfile.fitnessGoals
        if !goals.isEmpty {
            SettingsHairline()
            VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
                Text("Training Goals")
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                ForgeFlowLayout {
                    ForEach(goals) { goal in
                        ForgeChip(label: goal.label, energy: .ember, selected: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, FDS.Spacing.md)
        }
    }

    private var workoutGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Workout Preferences")
            SectionCard {
                settingsLink(
                    icon: "target",
                    iconColor: .ember,
                    label: "Training Goals",
                    trailingText: "\(store.userProfile.fitnessGoals.count)"
                ) { showGoalsEditor = true }

                SettingsHairline()
                preferredTypesRow

                SettingsHairline()
                settingsLink(
                    icon: "dumbbell.fill",
                    iconColor: .ember,
                    label: "Training Schedule",
                    trailingText: scheduleDays.isEmpty ? "Set days" : nil,
                    footnote: scheduleDays.isEmpty ? nil : scheduleDays
                ) { showScheduleEditor = true }

                SettingsHairline()
                settingsLink(
                    icon: store.userProfile.trainingEquipment.icon,
                    iconColor: .steel,
                    label: "Equipment",
                    trailingText: store.userProfile.trainingEquipment.rawValue
                ) { showEquipmentPicker = true }
            }
        }
    }

    private var preferredTypesRow: some View {
        let types = store.userProfile.preferredWorkouts
        return Button { showWorkoutsEditor = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    icon: "square.grid.2x2.fill",
                    iconColor: .ember,
                    label: "Preferred Types",
                    showChevron: true
                )
                if types.isEmpty {
                    rowFootnote("Tap to choose the sessions you actually do.")
                } else {
                    ForgeFlowLayout {
                        ForEach(types) { type in
                            ForgeChip(label: type.label)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, SettingsMetrics.labelInset)
                    .padding(.trailing, SettingsMetrics.rowInset)
                    .padding(.bottom, FDS.Spacing.md)
                }
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityHint("Opens Preferred Types")
    }

    private var nutritionGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Nutrition")
            SectionCard {
                settingsLink(
                    icon: "fork.knife",
                    iconColor: .amber,
                    label: "Nutrition Targets",
                    trailingText: nutritionTargetsAreCustom ? "Custom" : "Recommended"
                ) { showNutritionTargetsEditor = true }

                SettingsHairline()
                toggleRow(
                    icon: "fork.knife",
                    iconColor: .amber,
                    label: "Metabolic Health",
                    isOn: Binding(
                        get: { store.metabolicHealthEnabled },
                        set: { store.metabolicHealthEnabled = $0 }
                    )
                )
                rowFootnote("Meals ↔ glucose plus Apple Watch estimates. Turn it off to hide Metabolic everywhere.")
            }
        }
    }

    private var devicesGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Connected Devices")
            SectionCard {
                Color.clear.frame(width: 0, height: 0).hidden().id(catalogRevision)
                connectedDeviceRows
                SettingsHairline()
                settingsLink(
                    icon: "plus",
                    iconColor: .ember,
                    label: "Browse compatible devices"
                ) { showDevicesSheet = true }

                SettingsHairline()
                settingsLink(
                    icon: "rectangle.on.rectangle.badge.gearshape",
                    iconColor: .steel,
                    label: "Customize StandBy face"
                ) { showStandBySheet = true }
            }
        }
    }

    @ViewBuilder
    private var connectedDeviceRows: some View {
        if store.userProfile.connectedDevices.isEmpty {
            ForgeEmptyNote(
                title: "No devices yet.",
                message: "Browse the library — LARQ, Oura, Garmin, Watch and more.",
                systemImage: "link.badge.plus",
                tint: .steel
            )
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.vertical, FDS.Spacing.md)
        } else {
            let ids = HealthDeviceCatalog.migrateStoredIDs(store.userProfile.connectedDevices)
            ForEach(Array(ids.enumerated()), id: \.element) { idx, raw in
                if idx > 0 { SettingsHairline() }
                connectedDeviceRow(raw)
            }
        }
    }

    private func connectedDeviceRow(_ raw: String) -> some View {
        Button { showDevicesSheet = true } label: {
            SettingsDeviceRow(
                device: HealthDeviceCatalog.device(matching: raw),
                fallbackName: raw,
                live: store.healthKitLive
            )
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityHint("Opens your devices")
    }

    private var appleHealthGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Apple Health")
            SectionCard {
                SettingsRow(
                    icon: "heart.text.square.fill",
                    iconColor: store.healthKitLive ? Color.vitality : Color.warning,
                    label: "Apple Health",
                    trailingText: store.isHealthKitPulling
                        ? "Pulling…"
                        : (store.healthKitLive ? "Connected" : "Offline")
                ) {
                    if store.isHealthKitPulling {
                        ProgressView().controlSize(.mini)
                    }
                }
                .accessibilityElement(children: .combine)

                SettingsHairline()
                settingsLink(
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: .ember,
                    label: store.healthKitLive ? "Resync Apple Health" : "Reconnect Apple Health",
                    trailingText: "Now",
                    hint: "Pulls your latest Apple Health data"
                ) {
                    Task {
                        await store.reconnectHealthKit()
                        FDS.notificationHaptic(store.healthKitLive ? .success : .warning)
                    }
                }

                SettingsHairline()
                staticRow(
                    icon: "calendar.badge.clock",
                    iconColor: .steel,
                    label: "Cycle quiet sync",
                    trailingText: "Weekly"
                )
            }
            ingestErrorBanner
        }
    }

    @ViewBuilder
    private var ingestErrorBanner: some View {
        if let ingestError = store.lastLifeIngestError, !ingestError.isEmpty {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.warning)
                    .accessibilityHidden(true)
                Text(ingestError)
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
                    .forgeWrapping()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .forgeContentCard(tint: .warning, padding: ForgeLayout.compactCardPadding)
            .padding(.top, ForgeLayout.rowGap)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(ingestError)
        }
    }

    private var clinicalGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Clinical Data (Non PHI)")
            SectionCard {
                settingsLink(
                    icon: "pills.fill",
                    iconColor: .steel,
                    label: "Medicine & records",
                    trailingText: clinicalTrailingText
                ) { store.openClinicalData() }
            }
        }
    }

    // Cycle privacy (Home opens the full Cycle surface)
    private var cyclePrivacyGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Cycle privacy")
            SectionCard {
                cycleVaultBlock
                SettingsHairline()
                discretionBlock
                SettingsHairline()
                toggleRow(
                    icon: "faceid",
                    iconColor: .ember,
                    label: "Lock Cycle Health",
                    isOn: Binding(
                        get: { cycleStore.settings.cycleLockEnabled
                            || cycleStore.settings.discretionMode == .stealth },
                        set: { v in cycleStore.updateSettings { $0.cycleLockEnabled = v } }
                    )
                )
                SettingsHairline()
                toggleRow(
                    icon: "eye.fill",
                    iconColor: .ember,
                    label: "ARIA reads cycle on this iPhone",
                    isOn: Binding(
                        get: { cycleStore.settings.shareWithAria },
                        set: { v in cycleStore.updateSettings { $0.shareWithAria = v } }
                    )
                )
            }
        }
    }

    private var cycleVaultBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                icon: "lock.shield.fill",
                iconColor: .vitality,
                label: "Cycle Vault",
                trailingText: cycleStore.vaultSaveError == nil ? "Sealed" : "Retry"
            )
            .accessibilityElement(children: .combine)
            if let err = cycleStore.vaultSaveError {
                Button {
                    cycleStore.persistVault()
                } label: {
                    Text(err)
                        .font(HomeType.body)
                        .foregroundStyle(Color.danger)
                        .forgeWrapping()
                        .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap, alignment: .leading)
                        .padding(.leading, SettingsMetrics.labelInset)
                        .padding(.trailing, SettingsMetrics.rowInset)
                }
                .buttonStyle(SettingsRowButtonStyle())
                .accessibilityHint("Tries saving the vault again")
            }
        }
    }

    private var discretionBinding: Binding<CycleDiscretionMode> {
        Binding(
            get: { cycleStore.settings.discretionMode },
            set: { mode in cycleStore.updateSettings { $0.discretionMode = mode } }
        )
    }

    private var discretionOptions: [ForgeSegmentOption<CycleDiscretionMode>] {
        CycleDiscretionMode.allCases.map { mode in
            ForgeSegmentOption(value: mode, title: mode.label)
        }
    }

    private var discretionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                icon: "eye.slash.fill",
                iconColor: .steel,
                label: "Discretion mode"
            )
            ForgeSegmentedControl(
                discretionOptions,
                selection: discretionBinding,
                accent: .steel,
                bleed: SettingsMetrics.rowInset
            )
            .padding(.horizontal, SettingsMetrics.rowInset)
            .padding(.top, FDS.Spacing.xs)
            Text(cycleStore.settings.discretionMode.detail)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SettingsMetrics.rowInset)
                .padding(.top, ForgeLayout.rowGap)
                .padding(.bottom, FDS.Spacing.md)
        }
    }

    private var predictionAccuracyText: String {
        if let mae = cycleStore.accuracyReport.maeDays {
            return String(format: "MAE %.1fd", mae)
        }
        return "Learning"
    }

    private var cycleGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Cycle")
            SectionCard {
                settingsLink(
                    icon: "house.fill",
                    iconColor: .aurora,
                    label: "Open Cycle Health",
                    trailingText: "My cycle"
                ) { store.openCycleHealth() }

                SettingsHairline()
                settingsLink(
                    icon: "person.2.fill",
                    iconColor: .indigo,
                    label: "Open Support",
                    trailingText: "Partner"
                ) { store.openCycleHealth(pane: "partner") }

                SettingsHairline()
                staticRow(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: .ember,
                    label: "Prediction accuracy",
                    trailingText: predictionAccuracyText
                )

                SettingsHairline()
                toggleRow(
                    icon: "scope",
                    iconColor: .aurora,
                    label: "High-accuracy mode",
                    isOn: Binding(
                        get: { cycleStore.settings.highAccuracyMode },
                        set: { v in cycleStore.updateSettings { $0.highAccuracyMode = v } }
                    )
                )
            }
        }
    }

    private var notificationsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Notifications")
            SectionCard {
                toggleRow(
                    icon: "moon.fill",
                    iconColor: .steel,
                    label: "Quiet mode",
                    isOn: Binding(
                        get: { store.quietMode },
                        set: { store.setQuietMode($0) }
                    )
                )
                SettingsHairline()
                toggleRow(
                    icon: "figure.run",
                    iconColor: .ember,
                    label: "Workout Reminders",
                    isOn: notificationBinding(\.workoutReminders)
                )
                SettingsHairline()
                toggleRow(
                    icon: "text.bubble",
                    iconColor: .aurora,
                    label: "ARIA Proactive Briefs",
                    isOn: Binding(
                        get: { store.briefNotificationsEnabled },
                        set: { store.setBriefNotificationsEnabled($0) }
                    )
                )
                briefTimeRows
                SettingsHairline()
                settingsLink(
                    icon: "calendar.badge.clock",
                    iconColor: .ember,
                    label: "Weekly ARIA evaluation",
                    trailingText: weeklyReview.isDue ? "Due" : "Done"
                ) { weeklyReview.showSheet = true }

                SettingsHairline()
                toggleRow(
                    icon: "heart.fill",
                    iconColor: .steel,
                    label: "Sleep alerts",
                    isOn: notificationBinding(\.recoveryAlerts)
                )
                SettingsHairline()
                toggleRow(
                    icon: "calendar",
                    iconColor: .textSecondary,
                    label: "Weekly Summary",
                    isOn: notificationBinding(\.weeklySummary)
                )
                SettingsHairline()
                toggleRow(
                    icon: "drop.fill",
                    iconColor: .steel,
                    label: "Lifestyle Reminders",
                    isOn: notificationBinding(\.lifestyleReminders)
                )
                SettingsHairline()
                toggleRow(
                    icon: "moon.zzz.fill",
                    iconColor: .steel,
                    label: "Quiet week",
                    isOn: notificationBinding(\.sleepQuietWeek)
                )
            }
        }
    }

    @ViewBuilder
    private var briefTimeRows: some View {
        if store.briefNotificationsEnabled {
            SettingsHairline()
            briefTimeRow(
                icon: "sunrise.fill",
                iconColor: Color.amber,
                label: "Morning brief",
                hour: $briefSettings.morningHour,
                minute: $briefSettings.morningMinute
            )
            SettingsHairline()
            briefTimeRow(
                icon: "sunset.fill",
                iconColor: Color.indigo,
                label: "Evening brief",
                hour: $briefSettings.eveningHour,
                minute: $briefSettings.eveningMinute
            )
        }
    }

    private var dataPrivacyGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Data & Privacy")
            SectionCard {
                settingsLink(
                    icon: "lock.shield.fill",
                    iconColor: .steel,
                    label: "ARIA Data Permissions",
                    trailingText: "Manage"
                ) { showDataPermissions = true }

                SettingsHairline()
                ShareLink(item: store.exportUserDataJSON()) {
                    SettingsRow(
                        icon: "square.and.arrow.up",
                        iconColor: .ember,
                        label: "Export my data",
                        trailingText: "JSON",
                        showChevron: true
                    )
                }
                .buttonStyle(SettingsRowButtonStyle())
            }
        }
    }

    private var accountGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Account")
            SectionCard {
                staticRow(
                    icon: "person.crop.circle.fill",
                    iconColor: .ember,
                    label: store.authEmail.isEmpty ? "Signed in" : store.authEmail,
                    trailingText: store.authProvider.isEmpty ? "Session" : store.authProvider.capitalized
                )
                SettingsHairline()
                staticRow(
                    icon: "checkmark.shield.fill",
                    iconColor: .vitality,
                    label: "Session",
                    trailingText: store.isAuthenticated ? "Active" : "None"
                )
                SettingsHairline()
                staticRow(
                    icon: "clock.arrow.circlepath",
                    iconColor: .steel,
                    label: "Last sync",
                    trailingText: lastSyncText
                )
            }
        }
    }

    private var lastSyncText: String {
        if let at = store.lastCloudSyncAt ?? store.lastMetricsRefresh {
            return at.formatted(date: .omitted, time: .shortened)
        }
        return "Not yet"
    }

    private var moreGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("More")
            SectionCard {
                settingsLink(
                    icon: "lock.shield.fill",
                    iconColor: .textSecondary,
                    label: "Data & Privacy",
                    trailingText: "Apple Health + ARIA"
                ) { showDataPermissions = true }

                SettingsHairline()
                settingsLink(
                    icon: "doc.text.fill",
                    iconColor: .textSecondary,
                    label: "Privacy Policy",
                    trailingText: ForgeLegalConfig.privacyPolicyURL == nil ? "Required" : nil,
                    showChevron: ForgeLegalConfig.privacyPolicyURL != nil,
                    hint: "Opens the privacy policy"
                ) {
                    if let privacyPolicyURL = ForgeLegalConfig.privacyPolicyURL {
                        openURL(privacyPolicyURL)
                    } else {
                        showLocalPrivacy = true
                    }
                }

                SettingsHairline()
                settingsLink(
                    icon: "doc.plaintext.fill",
                    iconColor: .textSecondary,
                    label: "Terms & Conditions",
                    trailingText: "Local-first"
                ) { showTermsSheet = true }

                SettingsHairline()
                settingsLink(
                    icon: "creditcard.fill",
                    iconColor: .textSecondary,
                    label: "Subscription",
                    trailingText: "Ask ARIA"
                ) {
                    store.openChat(
                        with: "When can I subscribe to Forge? What does membership include?",
                        voice: false
                    )
                }

                SettingsHairline()
                // Opens a pre-addressed mail draft with the diagnostics a support reply needs.
                settingsLink(
                    icon: "questionmark.circle.fill",
                    iconColor: .textSecondary,
                    label: "Help & Support",
                    trailingText: "Email us",
                    hint: "Opens a pre-addressed email"
                ) { openSupportEmail() }

                SettingsHairline()
                settingsLink(
                    icon: "info.circle.fill",
                    iconColor: .textSecondary,
                    label: "About Forge",
                    trailingText: ForgeAppInfo.shortVersion
                ) { showAbout = true }

                SettingsHairline()
                settingsLink(
                    icon: "server.rack",
                    iconColor: .steel,
                    label: "ARIA backend URL",
                    trailingText: "Bedrock"
                ) { showBackendURL = true }
            }
        }
    }

    // Log Out: the last, quietest group. Confirmation dialog fires the destructive haptic.
    private var logOutButton: some View {
        ForgeSecondaryButton(
            title: "Log Out",
            icon: "rectangle.portrait.and.arrow.right",
            accent: Color.danger
        ) {
            confirmSignOut = true
        }
        .accessibilityHint("Asks you to confirm before logging out")
        .padding(.top, SettingsMetrics.sectionTop)
    }

    // MARK: - Row builders

    /// A tappable settings row. Press feedback and the haptic come from the
    /// row button style; a footnote sits under the label, inside the tap target.
    private func settingsLink(
        icon: String,
        iconColor: Color,
        label: String,
        trailingText: String? = nil,
        footnote: String? = nil,
        showChevron: Bool = true,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let resolvedHint: String = hint ?? (showChevron ? "Opens \(label)" : "")
        return Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    icon: icon,
                    iconColor: iconColor,
                    label: label,
                    trailingText: trailingText,
                    showChevron: showChevron
                )
                if let footnote, !footnote.isEmpty {
                    rowFootnote(footnote)
                }
            }
        }
        .buttonStyle(SettingsRowButtonStyle())
        .accessibilityHint(resolvedHint)
    }

    /// A non-interactive row read as one VoiceOver stop (label and value).
    private func staticRow(
        icon: String,
        iconColor: Color,
        label: String,
        trailingText: String? = nil
    ) -> some View {
        SettingsRow(icon: icon, iconColor: iconColor, label: label, trailingText: trailingText)
            .accessibilityElement(children: .combine)
    }

    /// A switch row. The switch carries the row's name for VoiceOver.
    private func toggleRow(
        icon: String,
        iconColor: Color,
        label: String,
        isOn: Binding<Bool>
    ) -> some View {
        SettingsRow(icon: icon, iconColor: iconColor, label: label) {
            ForgeToggle(isOn: isOn)
                .accessibilityLabel(label)
        }
    }

    /// Sentence under a row, aligned to the label column.
    private func rowFootnote(_ text: String) -> some View {
        Text(text)
            .font(HomeType.body)
            .foregroundStyle(Color.textSecondary)
            .forgeWrapping()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, SettingsMetrics.labelInset)
            .padding(.trailing, SettingsMetrics.rowInset)
            .padding(.top, -FDS.Spacing.sm)
            .padding(.bottom, FDS.Spacing.md)
    }

    private func coachPinChip(_ agent: AriaCoachAgent?, title: String) -> some View {
        ForgeChipButton(
            label: title,
            energy: .ember,
            selected: store.pinnedCoachAgent == agent
        ) {
            store.pinnedCoachAgent = agent
            if let agent { store.lastRoutedCoachAgent = agent }
        }
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

    func sectionHeader(_ title: String, subtitle: String? = nil) -> some View {
        ForgeSectionHeader(title: title, subtitle: subtitle)
            .padding(.top, SettingsMetrics.sectionTop)
            .padding(.bottom, SettingsMetrics.headerBottom)
    }
}

// MARK: - Settings layout helpers

/// Named rhythm for the Settings page. The section top and header bottom match
/// the headers that Your people and Life Context draw for themselves.
private enum SettingsMetrics {
    static let sectionTop: CGFloat = FDS.Spacing.xl
    static let headerBottom: CGFloat = FDS.Spacing.md
    static let rowInset: CGFloat = FDS.Spacing.lg
    /// Leading edge of a row label: row inset + 32 pt icon well + 12 pt gap.
    static let labelInset: CGFloat = 60
}

/// Inset hairline between rows of a settings card, aligned to the label column.
private struct SettingsHairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderHairline)
            .frame(height: ForgeUX.hairline)
            .padding(.leading, SettingsMetrics.labelInset)
            .accessibilityHidden(true)
    }
}

/// Plain row button with a press haptic and a quiet pressed state. It never
/// animates, so Reduce Motion needs no special case.
private struct SettingsRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { FDS.haptic(.press) }
            }
    }
}

/// A connected-device row: the product photo leads (36 pt), the name takes the
/// width, and a trailing caption names the source. The live dot only appears
/// while Apple Health is actually live.
private struct SettingsDeviceRow: View {
    let device: HealthDevice?
    let fallbackName: String
    let live: Bool

    private var title: String { device?.name ?? fallbackName }
    private var sourceText: String { device?.writesToAppleHealth == true ? "Health" : "iOS" }
    private var spokenLabel: String {
        live ? "\(title), \(sourceText), live" : "\(title), \(sourceText)"
    }

    @ViewBuilder
    private var leading: some View {
        if let device {
            DeviceProductImage(device: device, size: ForgeLayout.iconWell, cornerRadius: FDS.Radius.sm)
        } else {
            ForgeIconWell(systemImage: "sensor.tag.radiowaves.forward", tint: .steel)
        }
    }

    private var status: some View {
        HStack(spacing: FDS.Spacing.xs) {
            if live {
                Circle()
                    .fill(Color.vitality)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(sourceText)
                .font(HomeType.label)
                .foregroundStyle(Color.textSecondary)
                .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
        }
    }

    var body: some View {
        HStack(spacing: FDS.Spacing.md) {
            leading
            Text(title)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            status
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SettingsMetrics.rowInset)
        .padding(.vertical, ForgeLayout.rowVerticalPadding)
        .frame(minHeight: ForgeUX.minTap)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }
}
