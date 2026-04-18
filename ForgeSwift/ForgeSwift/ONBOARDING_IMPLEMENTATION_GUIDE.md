# FORGE - Data-Driven Onboarding Implementation Guide

## 🔥 Overview

This implementation creates a comprehensive, data-driven onboarding experience that leverages:

- **HealthKit**: Biometric data (heart rate, sleep, workouts, VO2 Max, HRV)
- **EventKit**: Calendar integration for smart workout scheduling
- **UserNotifications**: Intelligent workout reminders
- **Contacts**: Social features for workout buddies

## 📁 Files Created

### Core Managers
1. **HealthKitManager.swift**
   - Handles all HealthKit permissions and data fetching
   - Provides health snapshots and user profiles
   - Fetches: heart rate, steps, calories, sleep, workouts, VO2 Max, HRV
   - Includes age, weight, height from HealthKit

2. **OnboardingDataManager.swift**
   - Central manager for all onboarding data
   - Coordinates HealthKit, EventKit, Notifications, and Contacts
   - Provides smart recommendations based on user data
   - Analyzes calendar to suggest optimal workout times

### UI Components
3. **OnboardingHealthKitViews.swift**
   - HealthKitConnectionCard: Main connection UI
   - HealthDataPreviewCard: Shows recent health metrics
   - WearableInfoCard: Info cards for other devices
   - HealthMetricPill: Compact metric display

4. **EnhancedDataConnectionView.swift**
   - Replaces old DeviceConnectionView
   - Connects all data sources in one screen
   - Shows real-time connection status
   - Displays smart insights after connection

5. **SmartProfileSetupView.swift**
   - Enhanced profile setup with HealthKit integration
   - Auto-fills age, weight, height from HealthKit
   - Smart experience level recommendations based on VO2 Max and HRV
   - Shows health data in profile setup

6. **Info.plist.PERMISSIONS**
   - All required permission keys for Info.plist

## 🚀 Integration Steps

### Step 1: Add HealthKit Capability
1. In Xcode, select your project target
2. Go to **Signing & Capabilities**
3. Click **+ Capability**
4. Add **HealthKit**

### Step 2: Update Info.plist
Copy the contents of `Info.plist.PERMISSIONS` into your project's Info.plist file. These include:
- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription`
- `NSCalendarsUsageDescription`
- `NSCalendarsFullAccessUsageDescription`
- `NSContactsUsageDescription`
- `NSMotionUsageDescription`
- `NSLocationWhenInUseUsageDescription`

### Step 3: Update AppStore
Add a property to track HealthKit authorization in your `AppStore`:

```swift
@Published var healthKitAuthorized: Bool = false
```

### Step 4: Update OnboardingStepHost
Replace the old onboarding steps in your `OnboardingStepHost`:

```swift
struct OnboardingStepHost: View {
    @Binding var step: Int
    @EnvironmentObject var store: AppStore
    let onFinish: () -> Void

    var body: some View {
        Group {
            switch step {
            case 0:
                SmartProfileSetupView(onNext: { advance() })
            case 1:
                EnhancedDataConnectionView(onNext: { advance() })
            case 2:
                CoachingStyleView(onFinish: { onFinish() })
            default:
                EmptyView()
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
        .animation(.spring(response: 0.48, dampingFraction: 0.84), value: step)
    }

    private func advance() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) { step += 1 }
    }
}
```

## 📊 Features

### HealthKit Integration
- **Real-time Health Data**: Fetches and displays heart rate, steps, calories burned, and sleep
- **User Profile**: Auto-fills age, weight, height from HealthKit
- **Smart Recommendations**: Suggests experience level based on VO2 Max
- **Fitness Insights**: Analyzes HRV and recovery metrics

### Calendar Integration
- **Smart Scheduling**: Analyzes user's calendar for free time slots
- **Optimal Timing**: Identifies morning, lunch, and evening workout windows
- **Conflict Detection**: Avoids scheduling during existing events
- **Quality Ratings**: Marks slots as Optimal, Good, or Acceptable

### Notification System
- **Smart Reminders**: Schedules notifications based on suggested workout times
- **Personalized Timing**: Uses calendar analysis to set reminders
- **Customizable**: Users can adjust reminder preferences later

### Contacts Integration
- **Social Features**: Helps users find workout buddies
- **Privacy-Focused**: Only accesses contacts with permission
- **Invite System**: Built-in invite flow (to be implemented)

## 🎨 UI/UX Enhancements

### Visual Design
- **Connection Cards**: Beautiful cards for each data source
- **Real-time Feedback**: Immediate visual feedback on connection
- **Success States**: Celebrates when all data is connected
- **Smart Insights**: Shows actionable recommendations

### Animations
- **Spring Animations**: Smooth, natural feeling transitions
- **Staggered Appearance**: Cards appear sequentially for polish
- **Symbol Effects**: iOS 17+ symbol animations (.bounce, .pulse)
- **Scale Effects**: Subtle scale changes for engagement

### Data Display
- **Health Metrics Pills**: Compact, colorful display of key metrics
- **Workout Time Slots**: Calendar-style view of available times
- **Quality Indicators**: Color-coded quality badges
- **Recommendation Banners**: Highlighted smart insights

## 🧠 Smart Recommendations Logic

### Experience Level Detection
```swift
if vo2Max < 30 → Beginner
if vo2Max < 45 → Intermediate
if vo2Max >= 45 → Advanced
```

### Recovery Analysis
```swift
if HRV < 30ms → Under-recovered
if HRV > 60ms → Well-recovered
```

### Sleep Analysis
```swift
if sleep < 6 hours → Sleep warning
if sleep > 8 hours → Optimal recovery
```

### Activity Analysis
```swift
if steps < 5000 → Low activity warning
if steps > 10000 → Active lifestyle
```

## 📱 User Flow

1. **Authentication** → User signs in
2. **Smart Profile Setup** → Collects name, gender, goals
   - Auto-fills health data if HealthKit connected
   - Shows smart experience level recommendation
3. **Data Connection** → Connects HealthKit, Calendar, Notifications
   - Quick "Connect All" button
   - Individual connection options
   - Shows real-time insights
4. **Coaching Style** → User selects coaching preference
5. **Ready to Train** → Onboarding complete

## 🔒 Privacy & Permissions

All permissions are requested with clear explanations:
- **HealthKit**: "Personalize training based on biometrics"
- **Calendar**: "Suggest optimal workout times"
- **Notifications**: "Never miss a training session"
- **Contacts**: "Find workout buddies"

Users can:
- Skip any optional permissions
- Revisit in Settings later
- See exactly what data is used

## 🎯 Benefits

### For Users
- **Truly Personalized**: Training adapts to real health data
- **Smart Scheduling**: Workouts fit their actual schedule
- **Better Results**: Data-driven recommendations optimize progress
- **Time-Saving**: No manual data entry

### For the App
- **Higher Engagement**: Personalized experiences increase retention
- **Better Insights**: More data = smarter AI coaching
- **Competitive Advantage**: Few fitness apps use this much integration
- **Trust Building**: Transparent data usage builds user confidence

## 🐛 Testing Tips

1. **HealthKit**: Test on real device (not simulator)
2. **Calendar**: Create test events to verify conflict detection
3. **Notifications**: Check Settings → Notifications after permission
4. **Contacts**: Use test contacts, not your personal ones

## 🚧 Future Enhancements

- [ ] Workout route tracking with Location Services
- [ ] Integration with Apple Watch complications
- [ ] SharePlay for group workouts
- [ ] HealthKit writing (save completed workouts)
- [ ] Calendar event creation (auto-schedule workouts)
- [ ] StoreKit integration for premium features
- [ ] WidgetKit for home screen widgets

## 📝 Notes

- All managers use `@MainActor` for thread safety
- Async/await throughout for clean concurrency
- Error handling included but can be enhanced
- Ready for iOS 17+ features (symbol effects)
- Backward compatible with iOS 16 (checks availability)

## 🎓 Learning Resources

- [HealthKit Documentation](https://developer.apple.com/documentation/healthkit)
- [EventKit Documentation](https://developer.apple.com/documentation/eventkit)
- [UserNotifications Documentation](https://developer.apple.com/documentation/usernotifications)
- [Contacts Framework](https://developer.apple.com/documentation/contacts)

---

**Built with ❤️ for FORGE - Forge Your Strongest Self** 🔥
