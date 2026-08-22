import SwiftUI

struct RichCardView: View {
    let card: RichCardData
    var body: some View {
        switch card.type {
        case .workoutPlan: WorkoutRichCardView(card: card)
        case .dataChart:   DataChartRichCardView(card: card)
        }
    }
}

struct WorkoutRichCardView: View {
    let card: RichCardData
    @EnvironmentObject var store: AppStore
    @State private var expanded     = false
    @State private var startPressed = false
    @State private var appeared     = false

    var body: some View {
        VStack(spacing: 0) {
            FDS.Gradient.emberDeep.frame(height: 3)
                .cornerRadius(3, corners: [UIRectCorner.topLeft, UIRectCorner.topRight])

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.sm)
                        .fill(Color.ember.opacity(0.12)).frame(width: 46, height: 46)
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 19)).foregroundStyle(FDS.Gradient.ember)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.workoutName ?? "Workout Plan")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.textPrimary)
                    HStack(spacing: 12) {
                        Label("\(card.workoutDuration ?? 0) min", systemImage: "clock.fill")
                        Label("\(card.workoutExercises?.count ?? 0) exercises", systemImage: "list.bullet")
                    }
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.textSecondary)
                }
                Spacer()
                Button {
                    withAnimation(FDS.Spring.standard) { expanded.toggle() }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(FDS.Gradient.ember)
                }
            }
            .padding(16)

            if expanded, let exercises = card.workoutExercises {
                Divider().background(Color.borderColor.opacity(0.3))
                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.offset) { i, ex in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(Color.ember.opacity(0.1)).frame(width: 28, height: 28)
                                Text("\(i+1)").font(.system(size: 12, weight: .bold)).foregroundColor(.ember)
                            }
                            Text(ex.name).font(.system(size: 14, weight: .medium)).foregroundColor(.textPrimary)
                            Spacer()
                            Text("\(ex.sets) × \(ex.reps)")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.textSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.surface).cornerRadius(FDS.Radius.xs)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .forgeEntrance(index: i, appeared: expanded)
                        if i < exercises.count - 1 {
                            Divider().background(Color.borderColor.opacity(0.22)).padding(.leading, 56)
                        }
                    }
                }
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            Divider().background(Color.borderColor.opacity(0.3))

            Button {
                store.startWorkout(); store.activeTab = .workout
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                    Text("Start This Workout").font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(FDS.Gradient.emberDeep).cornerRadius(FDS.Radius.sm)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: FDS.Radius.sm)
                        .fill(LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center))
                        .frame(height: 20)
                }
                .shadow(color: Color.ember.opacity(startPressed ? 0.2 : 0.42), radius: startPressed ? 4 : 12, y: startPressed ? 1 : 5)
                .scaleEffect(startPressed ? 0.97 : 1).animation(FDS.Spring.snap, value: startPressed)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in startPressed = true }.onEnded { _ in startPressed = false })
            .padding(14)
        }
        .background(Color.surface)
        .cornerRadius(FDS.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(Color.ember.opacity(0.2), lineWidth: 1))
        .shadow(color: Color.ember.opacity(0.08), radius: 14, y: 5)
        .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
        .opacity(appeared ? 1 : 0).offset(y: appeared ? 0 : 10)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true } }
    }
}

struct DataChartRichCardView: View {
    let card: RichCardData
    @State private var appeared = false
    @State private var hoverIdx: Int? = nil
    var values:   [Double] { card.chartValues ?? [] }
    var maxVal:   Double   { values.max() ?? 1 }
    var minVal:   Double   { values.min() ?? 0 }
    var barColor: Color    { card.chartColor ?? .steel }

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [barColor.opacity(0.75), barColor.opacity(0.35)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 3).cornerRadius(3, corners: [UIRectCorner.topLeft, UIRectCorner.topRight])

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: FDS.Radius.xs).fill(barColor.opacity(0.14)).frame(width: 38, height: 38)
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 16)).foregroundColor(barColor)
                }
                Text(card.chartTitle ?? "Trend")
                    .font(.system(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                Spacer()
                if let idx = hoverIdx, idx < values.count {
                    Text(String(format: "%.0f", values[idx]))
                        .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(barColor)
                        .transition(.opacity)
                }
            }
            .padding(14)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                        let norm = maxVal > minVal ? (val - minVal) / (maxVal - minVal) : 1
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: [barColor.opacity(hoverIdx == i ? 0.95 : 0.55 + 0.45 * norm),
                                         barColor.opacity(hoverIdx == i ? 0.65 : 0.28 + 0.37 * norm)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(maxWidth: .infinity)
                            .frame(height: appeared ? max(6, 52 * CGFloat(norm)) : 4)
                            .scaleEffect(y: hoverIdx == i ? 1.07 : 1.0, anchor: .bottom)
                            .animation(FDS.Spring.hero.delay(Double(i) * 0.04), value: appeared)
                            .animation(FDS.Spring.snap, value: hoverIdx)
                            .onTapGesture {
                                withAnimation(FDS.Spring.snap) { hoverIdx = hoverIdx == i ? nil : i }
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                    }
                }
                .frame(height: 52)
                if let insight = card.chartInsight {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill").font(.system(size: 12)).foregroundColor(barColor.opacity(0.75))
                        Text(insight).font(.system(size: 13, weight: .medium)).foregroundColor(.textSecondary).lineSpacing(3)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: FDS.Radius.sm).fill(barColor.opacity(0.04)))
            .padding(12)
        }
        .background(Color.surface).cornerRadius(FDS.Radius.md)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md).stroke(barColor.opacity(0.2), lineWidth: 1))
        .shadow(color: barColor.opacity(0.07), radius: 10, y: 4)
        .onAppear { withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true } }
    }
}

// MARK: - readinessColor helper
private func readinessColor(_ score: Int) -> Color {
    switch score {
    case 85...:   return Color(hex: "22C55E")
    case 70..<85: return Color.ember
    case 50..<70: return Color.steel
    default:      return Color(hex: "EF4444")
    }
}
