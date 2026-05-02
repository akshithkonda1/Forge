import Foundation
import HealthKit
import EventKit
import UserNotifications
import Contacts

// MARK: - Onboarding Data Manager

@MainActor
class OnboardingDataManager: ObservableObject {
    static let shared = OnboardingDataManager()
    
    // Managers
    private let healthKitManager = HealthKitManager.shared
    private let eventStore = EKEventStore()
    private let notificationCenter = UNUserNotificationCenter.current()
    
    // Published state
    @Published var healthKitAuthorized = false
    @Published var calendarAuthorized = false
    @Published var notificationsAuthorized = false
    @Published var contactsAuthorized = false
    
    @Published var healthProfile: UserHealthProfile?
    @Published var healthSnapshot: HealthDataSnapshot?
    @Published var suggestedWorkoutTimes: [WorkoutTimeSlot] = []
    @Published var contactsWithFitnessInterest: [FitnessContact] = []
    
    @Published var isLoadingHealthData = false
    @Published var isAnalyzingCalendar = false
    
    private init() {}
    
    // MARK: - Comprehensive Authorization
    
    func requestAllPermissions() async {
        async let health = requestHealthKitPermission()
        async let calendar = requestCalendarPermission()
        async let notifications = requestNotificationPermission()
        async let contacts = requestContactsPermission()
        
        _ = await (health, calendar, notifications, contacts)
        
        // Fetch initial data
        await fetchAllOnboardingData()
    }
    
    // MARK: - HealthKit Integration
    
    func requestHealthKitPermission() async -> Bool {
        do {
            try await healthKitManager.requestAuthorization()
            healthKitAuthorized = true
            return true
        } catch {
            print("HealthKit authorization failed: \(error)")
            return false
        }
    }
    
    func fetchHealthData() async {
        guard healthKitAuthorized else { return }
        isLoadingHealthData = true
        
        async let profile = healthKitManager.fetchUserProfile()
        async let snapshot = healthKitManager.fetchRecentSnapshot()
        
        let (profileData, snapshotData) = await (profile, snapshot)
        
        healthProfile = profileData
        healthSnapshot = snapshotData
        isLoadingHealthData = false
    }
    
    // MARK: - Calendar Integration (EventKit)
    
    func requestCalendarPermission() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            calendarAuthorized = granted
            return granted
        } catch {
            print("Calendar authorization failed: \(error)")
            return false
        }
    }
    
    func analyzeCalendarForWorkoutSlots() async {
        guard calendarAuthorized else { return }
        isAnalyzingCalendar = true
        
        let calendar = Calendar.current
        let now = Date()
        let oneWeekAhead = calendar.date(byAdding: .day, value: 7, to: now)!
        
        let predicate = eventStore.predicateForEvents(withStart: now, end: oneWeekAhead, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        // Analyze free time slots
        let slots = findOptimalWorkoutSlots(from: events, in: now...oneWeekAhead)
        suggestedWorkoutTimes = slots
        isAnalyzingCalendar = false
    }
    
    private func findOptimalWorkoutSlots(from events: [EKEvent], in dateRange: ClosedRange<Date>) -> [WorkoutTimeSlot] {
        var slots: [WorkoutTimeSlot] = []
        let calendar = Calendar.current
        
        // Define optimal workout times
        let optimalTimeRanges: [(start: Int, end: Int, quality: WorkoutTimeQuality)] = [
            (6, 8, .optimal),     // Early morning
            (12, 13, .good),      // Lunch
            (17, 19, .optimal),   // Evening
        ]
        
        var currentDate = dateRange.lowerBound
        
        while currentDate <= dateRange.upperBound {
            for timeRange in optimalTimeRanges {
                guard let slotStart = calendar.date(bySettingHour: timeRange.start, minute: 0, second: 0, of: currentDate),
                      let slotEnd = calendar.date(bySettingHour: timeRange.end, minute: 0, second: 0, of: currentDate) else {
                    continue
                }
                
                // Check if this slot conflicts with any events
                let hasConflict = events.contains { event in
                    guard let eventStart = event.startDate, let eventEnd = event.endDate else { return false }
                    return (eventStart < slotEnd && eventEnd > slotStart)
                }
                
                if !hasConflict {
                    let slot = WorkoutTimeSlot(
                        date: slotStart,
                        startTime: slotStart,
                        endTime: slotEnd,
                        duration: timeRange.end - timeRange.start,
                        quality: timeRange.quality,
                        dayOfWeek: calendar.component(.weekday, from: slotStart)
                    )
                    slots.append(slot)
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        // Return top 5 slots
        return Array(slots.prefix(5))
    }
    
    // MARK: - Notifications Permission
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            notificationsAuthorized = granted
            return granted
        } catch {
            print("Notification authorization failed: \(error)")
            return false
        }
    }
    
    func scheduleInitialWorkoutReminders() async {
        guard notificationsAuthorized else { return }
        
        // Remove existing notifications
        notificationCenter.removeAllPendingNotificationRequests()
        
        // Schedule based on suggested workout times
        for (index, slot) in suggestedWorkoutTimes.prefix(3).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Time to Train 🔥"
            content.body = "You have a \(slot.duration)-hour workout window. Let's crush it!"
            content.sound = .default
            content.categoryIdentifier = "WORKOUT_REMINDER"
            
            let components = Calendar.current.dateComponents([.hour, .minute], from: slot.startTime)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            
            let request = UNNotificationRequest(
                identifier: "workout_\(index)",
                content: content,
                trigger: trigger
            )
            
            try? await notificationCenter.add(request)
        }
    }
    
    // MARK: - Contacts Integration
    
    func requestContactsPermission() async -> Bool {
        let store = CNContactStore()
        do {
            let granted = try await store.requestAccess(for: .contacts)
            contactsAuthorized = granted
            return granted
        } catch {
            print("Contacts authorization failed: \(error)")
            return false
        }
    }
    
    func findFitnessContacts() async {
        guard contactsAuthorized else { return }
        
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactImageDataKey] as [CNKeyDescriptor]
        let request = CNContactFetchRequest(keysToFetch: keys)
        
        var contacts: [FitnessContact] = []
        
        do {
            try store.enumerateContacts(with: request) { contact, _ in
                // Simple heuristic: first 5 contacts as potential workout buddies
                if contacts.count < 5 {
                    let fitnessContact = FitnessContact(
                        id: contact.identifier,
                        firstName: contact.givenName,
                        lastName: contact.familyName,
                        photoData: contact.imageData,
                        inviteStatus: .notInvited
                    )
                    contacts.append(fitnessContact)
                }
            }
            contactsWithFitnessInterest = contacts
        } catch {
            print("Failed to fetch contacts: \(error)")
        }
    }
    
    // MARK: - Fetch All Data
    
    func fetchAllOnboardingData() async {
        async let health = fetchHealthData()
        async let calendar = analyzeCalendarForWorkoutSlots()
        async let contacts = findFitnessContacts()
        
        _ = await (health, calendar, contacts)
    }
    
    // MARK: - Smart Recommendations
    
    func generatePersonalizedRecommendations() -> OnboardingRecommendations {
        var recs = OnboardingRecommendations()
        
        // Health-based recommendations
        if let profile = healthProfile {
            if let vo2Max = profile.vo2Max {
                if vo2Max < 30 {
                    recs.suggestedExperienceLevel = .beginner
                    recs.workoutIntensityAdvice = "Start with low-intensity cardio to build your aerobic base."
                } else if vo2Max < 45 {
                    recs.suggestedExperienceLevel = .intermediate
                    recs.workoutIntensityAdvice = "You have a solid fitness base. Mix HIIT and strength training."
                } else {
                    recs.suggestedExperienceLevel = .advanced
                    recs.workoutIntensityAdvice = "Your cardio capacity is excellent. Focus on power and technique."
                }
            }
            
            if let hrv = profile.averageHRV {
                if hrv < 30 {
                    recs.recoveryAdvice = "Your HRV suggests you may be under-recovered. Prioritize sleep and active recovery."
                } else if hrv > 60 {
                    recs.recoveryAdvice = "Excellent recovery markers! You can handle high training loads."
                }
            }
        }
        
        // Snapshot-based recommendations
        if let snapshot = healthSnapshot {
            if let sleep = snapshot.sleepHours, sleep < 6 {
                recs.sleepAdvice = "You're averaging under 6 hours of sleep. This will limit your gains."
            }
            
            if let steps = snapshot.steps, steps < 5000 {
                recs.activityAdvice = "Consider adding more daily movement outside of structured workouts."
            }
        }
        
        // Calendar-based recommendations
        if !suggestedWorkoutTimes.isEmpty {
            let morningSlots = suggestedWorkoutTimes.filter { Calendar.current.component(.hour, from: $0.startTime) < 12 }
            if morningSlots.count >= 3 {
                recs.scheduleAdvice = "You have consistent morning availability. Morning workouts boost metabolism all day."
            }
        }
        
        return recs
    }
}

// MARK: - Supporting Types

struct WorkoutTimeSlot: Identifiable {
    let id = UUID()
    let date: Date
    let startTime: Date
    let endTime: Date
    let duration: Int // hours
    let quality: WorkoutTimeQuality
    let dayOfWeek: Int
    
    var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }
    
    var dayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
}

enum WorkoutTimeQuality {
    case optimal, good, acceptable
    
    var color: String {
        switch self {
        case .optimal: return "success"
        case .good: return "ember"
        case .acceptable: return "steel"
        }
    }
    
    var label: String {
        switch self {
        case .optimal: return "Optimal"
        case .good: return "Good"
        case .acceptable: return "OK"
        }
    }
}

struct FitnessContact: Identifiable {
    let id: String
    let firstName: String
    let lastName: String
    let photoData: Data?
    var inviteStatus: InviteStatus
    
    var fullName: String {
        "\(firstName) \(lastName)"
    }
}

enum InviteStatus {
    case notInvited, invited, joined
}

struct OnboardingRecommendations {
    var suggestedExperienceLevel: ExperienceLevel?
    var workoutIntensityAdvice: String?
    var recoveryAdvice: String?
    var sleepAdvice: String?
    var activityAdvice: String?
    var scheduleAdvice: String?
    
    var hasRecommendations: Bool {
        workoutIntensityAdvice != nil || recoveryAdvice != nil || sleepAdvice != nil || activityAdvice != nil || scheduleAdvice != nil
    }
}
