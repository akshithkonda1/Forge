# 🚀 Quick Start Checklist

## Immediate Setup (5 minutes)

### 1. Add Files to Xcode
- [x] Drag all new `.swift` files into your Xcode project
- [x] Ensure they're added to your app target (check the checkbox)
- [x] Files to add:
  - `HealthKitManager.swift`
  - `OnboardingDataManager.swift`
  - `OnboardingHealthKitViews.swift`
  - `EnhancedDataConnectionView.swift`
  - `SmartProfileSetupView.swift`
  - `ColorExtensions.swift`

### 2. Add HealthKit Capability
- [x] Select your project in Xcode
- [x] Go to **Signing & Capabilities** tab
- [x] Click **+ Capability**
- [x] Search for and add **HealthKit**

### 3. Update Info.plist
Copy these keys from `Info.plist.PERMISSIONS` into your `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>FORGE needs access to your health data to create personalized training plans based on your heart rate, workouts, sleep patterns, and activity levels.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>FORGE can save your workouts to the Health app to keep all your fitness data in one place and track your progress over time.</string>

<key>NSCalendarsFullAccessUsageDescription</key>
<string>FORGE needs full calendar access to intelligently schedule workouts around your meetings and events for maximum consistency.</string>

<key>NSContactsUsageDescription</key>
<string>FORGE can help you find workout buddies from your contacts to make training more social and motivating.</string>
```

### 4. Update AppStore
Add this property to your `AppStore` class:

```swift
@Published var healthKitAuthorized: Bool = false
@Published var userProfile = UserProfile() // Make sure this exists
```

### 5. Update OnboardingStepHost
Replace your existing onboarding steps:

```swift
case 0:
    SmartProfileSetupView(onNext: { advance() })
case 1:
    EnhancedDataConnectionView(onNext: { advance() })
case 2:
    CoachingStyleView(onFinish: { onFinish() })
```

## Testing Checklist

### HealthKit
- [ ] Run on **real device** (HealthKit doesn't work in simulator)
- [ ] Grant HealthKit permission when prompted
- [ ] Check that health data appears in profile setup
- [ ] Verify metrics show in data preview card

### Calendar
- [ ] Create some test calendar events
- [ ] Grant calendar permission
- [ ] Verify suggested workout times appear
- [ ] Check that times don't conflict with events

### Notifications
- [ ] Grant notification permission
- [ ] Check Settings → Notifications → YourApp
- [ ] Verify notifications are enabled

### Contacts
- [ ] Grant contacts permission
- [ ] Verify some contacts appear (optional feature)

## Common Issues & Fixes

### ⚠️ "HealthKit not available"
**Fix**: HealthKit only works on real iOS devices, not simulator

### ⚠️ "Module 'HealthKit' not found"
**Fix**: Make sure you added the HealthKit capability in Signing & Capabilities

### ⚠️ "Calendar permission denied"
**Fix**: Go to Settings → Privacy → Calendars → YourApp and enable

### ⚠️ Colors not showing correctly
**Fix**: Make sure `ColorExtensions.swift` is added to your project

### ⚠️ Missing types (Gender, ExperienceLevel, etc.)
**Fix**: These should be in your existing `AppModels.swift`. If not, create them:

```swift
enum Gender: String, CaseIterable, Identifiable {
    case male, female, preferNotToSay
    var id: String { rawValue }
    var label: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .preferNotToSay: return "Prefer not to say"
        }
    }
    var icon: String {
        switch self {
        case .male: return "person.fill"
        case .female: return "person.fill"
        case .preferNotToSay: return "person.fill.questionmark"
        }
    }
}

enum ExperienceLevel: String, CaseIterable, Identifiable {
    case beginner, intermediate, advanced, elite
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var description: String {
        switch self {
        case .beginner: return "New to fitness"
        case .intermediate: return "Regular training"
        case .advanced: return "Serious athlete"
        case .elite: return "Competitive level"
        }
    }
}
```

## Verification

Run through the complete onboarding flow:

1. **Auth Screen** → Sign in
2. **Profile Setup** → Should show HealthKit data if connected
3. **Data Connection** → Connect all services
   - Should see "All Systems Connected" banner
   - Should see health metrics card
   - Should see suggested workout times
4. **Coaching Style** → Select preference
5. **Main App** → Should load with all data

## What You Get

✅ **Real Health Data**: Heart rate, sleep, workouts from HealthKit  
✅ **Smart Scheduling**: AI finds best workout times from calendar  
✅ **Auto-filled Profile**: Age, weight, height from HealthKit  
✅ **Smart Recommendations**: Experience level based on VO2 Max  
✅ **Beautiful UI**: Polished animations and transitions  
✅ **Privacy-First**: Clear explanations, optional permissions  

## Performance Tips

- HealthKit queries run async - won't block UI
- Calendar analysis is fast (< 1 second for week of events)
- Data is cached in OnboardingDataManager
- All animations use spring physics for natural feel

## Next Steps

After basic setup works:

1. **Customize Colors**: Update `Color.ember` and other brand colors
2. **Add More Metrics**: Extend HealthKitManager for more data types
3. **Enhance Recommendations**: Improve the AI suggestion logic
4. **Add Persistence**: Save permissions state to UserDefaults
5. **Create Settings**: Let users reconnect data sources later

## Support

If you run into issues:

1. Check ONBOARDING_IMPLEMENTATION_GUIDE.md for details
2. Verify all Info.plist keys are added
3. Confirm HealthKit capability is enabled
4. Test on real device, not simulator
5. Check Xcode console for error messages

---

**Ready to ship? Let's go! 🔥**
