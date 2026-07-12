import SwiftUI

// MARK: - HealthKit Connection Card

struct HealthKitConnectionCard: View {
    @Binding var isConnected: Bool
    @Binding var isRequesting: Bool
    let onConnect: () -> Void
    let index: Int
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isConnected ? Color.success.opacity(0.12) : Color.ember.opacity(0.12))
                    .frame(width: 56, height: 56)
                
                if isRequesting {
                    ProgressView()
                        .tint(isConnected ? .success : .ember)
                } else {
                    Image(systemName: isConnected ? "checkmark.seal.fill" : "heart.text.square.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(isConnected ? .success : .ember)
                        .symbolEffect(.bounce, value: isConnected)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("HealthKit")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Text(isConnected 
                    ? "Connected • Syncing biometric data"
                    : "Access your health & fitness data")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                    .lineLimit(2)
            }

            Spacer()

            if !isConnected {
                Button {
                    onConnect()
                } label: {
                    Text("Connect")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.ember, Color(hex: "FF5A00")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(10)
                        .shadow(color: Color.ember.opacity(0.3), radius: 8, y: 3)
                }
                .disabled(isRequesting)
                .accessibilityLabel("Connect Apple Health")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.success)
                    .accessibilityLabel("Apple Health connected")
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isConnected ? Color.success.opacity(0.4) : Color.ember.opacity(0.3),
                    lineWidth: isConnected ? 2 : 1
                )
        )
        .shadow(
            color: isConnected ? Color.success.opacity(0.15) : Color.ember.opacity(0.08),
            radius: isConnected ? 14 : 8,
            y: 4
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(index) * 0.06)) {
                appeared = true
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isConnected)
    }
}

// MARK: - Wearable Info Card (non-functional, informational)

struct WearableInfoCard: View {
    let name: String
    let icon: String
    let desc: String
    let index: Int
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.steel.opacity(0.08))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.steel)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.textMuted)
            }

            Spacer()
            
            Text("Auto")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.steel.opacity(0.1))
                .cornerRadius(6)
        }
        .padding(13)
        .background(Color.surface.opacity(0.5))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.borderColor.opacity(0.3), lineWidth: 1)
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(Double(index) * 0.06)) {
                appeared = true
            }
        }
    }
}

// MARK: - Health Data Preview Card

struct HealthDataPreviewCard: View {
    let snapshot: HealthDataSnapshot
    @State private var appeared = false
    
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
                Text("Recent Health Data")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("Today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
            
            HStack(spacing: 10) {
                if let hr = snapshot.restingHeartRate {
                    HealthMetricPill(icon: "heart.fill", value: "\(hr)", unit: "BPM", color: .ember)
                }
                if let steps = snapshot.steps {
                    HealthMetricPill(icon: "figure.walk", value: formatNumber(steps), unit: "steps", color: .blue)
                }
                if let cals = snapshot.activeCalories {
                    HealthMetricPill(icon: "flame.fill", value: "\(cals)", unit: "kcal", color: .orange)
                }
            }
            
            if let sleep = snapshot.sleepHours {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.purple)
                    Text("**\(String(format: "%.1f", sleep))h** sleep last night")
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.ember.opacity(0.04))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        LinearGradient(
                            colors: [Color.ember.opacity(0.3), Color.ember.opacity(0.1)],
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
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1000 {
            return String(format: "%.1fk", Double(num) / 1000)
        }
        return "\(num)"
    }
}

// MARK: - Health Metric Pill

struct HealthMetricPill: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text(unit)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.surface)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}
