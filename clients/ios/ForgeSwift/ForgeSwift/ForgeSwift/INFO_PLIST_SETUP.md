# Info.plist Configuration Guide

## Required Entitlements and Privacy Strings

### 1. HealthKit Configuration

Add to your `Info.plist`:

```xml
<!-- HealthKit Usage -->
<key>NSHealthShareUsageDescription</key>
<string>FORGE needs access to your health data to provide personalized workout recommendations, track your progress, and optimize your nutrition. Your data never leaves your device.</string>

<key>NSHealthUpdateUsageDescription</key>
<string>FORGE will log your meals, water intake, and workouts to HealthKit so all your health data stays in one place. This enables seamless integration with Apple Health.</string>

<!-- HealthKit Capabilities -->
<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>healthkit</string>
</array>
```

### 2. Notifications

```xml
<!-- Push Notifications -->
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

### 3. Location (Optional - for outdoor workout tracking)

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>FORGE uses your location to track outdoor workouts like runs and bike rides, providing accurate distance and route information.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>FORGE can track outdoor workouts in the background, allowing you to see your route and distance even if the app isn't open.</string>
```

---

## Xcode Project Settings

### 1. Signing & Capabilities Tab

Add these capabilities:

#### HealthKit
1. Click "+ Capability"
2. Select "HealthKit"
3. Check "Clinical Health Records" (optional)
4. Check "Background Delivery"

#### Push Notifications
1. Click "+ Capability"
2. Select "Push Notifications"

#### Background Modes
1. Click "+ Capability"
2. Select "Background Modes"
3. Enable:
   - ✅ Background fetch
   - ✅ Remote notifications
   - ✅ Location updates (if using GPS workouts)

---

## HealthKit Entitlements File

Your `YourApp.entitlements` should include:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- HealthKit -->
    <key>com.apple.developer.healthkit</key>
    <true/>
    
    <key>com.apple.developer.healthkit.access</key>
    <array>
        <string>health-records</string>
    </array>
    
    <!-- Push Notifications (if using) -->
    <key>aps-environment</key>
    <string>development</string>
    <!-- Change to 'production' for App Store builds -->
    
    <!-- Background Modes -->
    <key>com.apple.developer.healthkit.background-delivery</key>
    <true/>
</dict>
</plist>
```

---

## App Transport Security (if using any HTTP APIs)

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <!-- Or configure specific exceptions -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>yourapi.com</key>
        <dict>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <false/>
        </dict>
    </dict>
</dict>
```

---

## Testing HealthKit on Simulator

### Simulator Setup:
1. Open Health app in simulator
2. Go to "Browse" → "Other Data"
3. Manually add sample data for:
   - Steps
   - Active Energy
   - Heart Rate
   - Sleep Analysis
   - Nutrition data

### Debug Menu:
- Features → Health → Auto-generate Health Data (for testing)

---

## Production Checklist

Before submitting to App Store:

- [ ] HealthKit entitlements enabled
- [ ] Privacy strings added to Info.plist
- [ ] Tested HealthKit authorization flow
- [ ] Verified data read/write permissions
- [ ] Tested on real device (not just simulator)
- [ ] Background delivery working correctly
- [ ] Notification permissions flow tested
- [ ] Privacy Policy mentions HealthKit usage
- [ ] App Store screenshots show health data with consent

---

## App Store Review Guidelines

### HealthKit-Specific:

1. **Data Usage Transparency**
   - Clearly explain why you need each health data type
   - Show users exactly what data you access
   - Never share health data with third parties

2. **Primary Purpose**
   - Your app must have health/fitness as a primary function
   - HealthKit data must be essential to core features

3. **Privacy Policy**
   - Must include HealthKit usage section
   - Explain data retention policy
   - Clarify that data doesn't leave the device

4. **User Consent**
   - Request minimum necessary data types
   - Allow users to deny some permissions
   - App must remain functional without full HealthKit access

---

## Common Issues & Solutions

### Issue: HealthKit Authorization Always Fails
**Solution:**
- Check entitlements are properly configured
- Verify Info.plist privacy strings are present
- Ensure running on real device (HealthKit limited on simulator)
- Check bundle identifier matches provisioning profile

### Issue: Background Delivery Not Working
**Solution:**
- Enable "Background Delivery" in HealthKit capability
- Request authorization with background delivery option
- Implement HKObserverQuery for background updates

### Issue: "Health Data Unavailable"
**Solution:**
- Check `HKHealthStore.isHealthDataAvailable()`
- iPod touch doesn't support HealthKit
- Some countries may restrict HealthKit

### Issue: Data Not Syncing Immediately
**Solution:**
- HealthKit has intentional delays for privacy
- Use executeQuery instead of waiting for updates
- Consider implementing manual refresh

---

## Best Practices

1. **Request Minimum Permissions**
   - Only ask for data types you actually use
   - Request write permissions separately from read

2. **Graceful Degradation**
   - App should work without full HealthKit access
   - Provide manual entry fallback

3. **Privacy First**
   - Never cache health data unnecessarily
   - Process data on-device when possible
   - Be transparent about data usage

4. **User Experience**
   - Explain benefits before requesting permissions
   - Show example of how data improves experience
   - Allow users to skip (with reduced functionality)

---

## Example Authorization Flow

```swift
// 1. Check availability
guard HKHealthStore.isHealthDataAvailable() else {
    // Show fallback UI
    return
}

// 2. Request minimal permissions first
let basicTypes: Set<HKObjectType> = [
    HKObjectType.quantityType(forIdentifier: .stepCount)!,
    HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
]

try await healthStore.requestAuthorization(toShare: [], read: basicTypes)

// 3. Request additional permissions later when needed
let advancedTypes: Set<HKObjectType> = [
    HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
]

try await healthStore.requestAuthorization(toShare: [], read: advancedTypes)
```

---

## Resources

- [HealthKit Documentation](https://developer.apple.com/documentation/healthkit)
- [App Store Review Guidelines - HealthKit](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research)
- [WWDC Sessions on HealthKit](https://developer.apple.com/videos/healthkit)
- [Human Interface Guidelines - Health](https://developer.apple.com/design/human-interface-guidelines/healthkit)

---

## Support

For HealthKit-specific issues:
- Apple Developer Forums: forums.developer.apple.com
- Technical Support Incidents (TSI)
- WWDC Labs (during WWDC week)

---

Last Updated: April 27, 2026
