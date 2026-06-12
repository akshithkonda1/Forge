import SwiftUI

struct ForgeWatchContentView: View {
    @EnvironmentObject private var workout: ForgeWatchWorkoutSessionManager
    @EnvironmentObject private var connectivity: ForgeWatchConnectivityManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            readinessTab.tag(0)
            workoutTab.tag(1)
        }
        .tabViewStyle(.verticalPage)
        .onReceive(NotificationCenter.default.publisher(for: .forgePhoneWorkoutStateChanged)) { _ in
            Task { await syncWithPhoneWorkoutState() }
        }
        .task {
            await syncWithPhoneWorkoutState()
        }
    }

    private var readinessTab: some View {
        VStack(spacing: 10) {
            Text("FORGE")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.orange)

            HStack(spacing: 8) {
                WatchTrilogyStat(label: "Strain", value: ForgeWatchDashboardReader.strainScore, color: .orange)
                WatchTrilogyStat(label: "Rec", value: ForgeWatchDashboardReader.recoveryScore, color: .green)
                WatchTrilogyStat(label: "Sleep", value: ForgeWatchDashboardReader.sleepScore, color: .indigo)
            }

            Text(ForgeWatchDashboardReader.workoutName)
                .font(.caption)
                .lineLimit(1)

            Text("Ready \(ForgeWatchDashboardReader.readinessScore) · \(ForgeWatchDashboardReader.streak)d streak")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if connectivity.isPhoneReachable {
                Label("iPhone connected", systemImage: "iphone")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding()
    }

    private var workoutTab: some View {
        VStack(spacing: 12) {
            if workout.isActive {
                Text(workout.workoutName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(workout.heartRate > 0 ? "\(workout.heartRate)" : "—")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                    Text("bpm")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if workout.spO2 > 0 {
                    Text("O₂ \(workout.spO2)%")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                }

                Text(formatElapsed(workout.elapsedSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button("End") {
                    Task { await workout.endWorkout() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                Text("Start on iPhone or tap below")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if let error = workout.lastError {
                    Text(error)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.red)
                }

                Button("Start Workout") {
                    Task { await workout.startWorkout(name: ForgeWatchDashboardReader.workoutName) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
    }

    private func syncWithPhoneWorkoutState() async {
        if ForgeWatchVitalsBridge.isPhoneWorkoutActive, !workout.isActive {
            await workout.startWorkout(name: ForgeWatchVitalsBridge.phoneWorkoutName)
        } else if !ForgeWatchVitalsBridge.isPhoneWorkoutActive, workout.isActive,
                  workout.startedByPhone {
            await workout.endWorkout()
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private struct WatchTrilogyStat: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}