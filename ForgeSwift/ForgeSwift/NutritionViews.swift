import SwiftUI
import UIKit
import AVFoundation

// MARK: - Daily Nutrition View (Macro Rings flagship)

struct DailyNutritionView: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 20) {
            AINutritionCoachCard(vm: vm)
            MacroRingsCard(vm: vm)
            MealLogCard(vm: vm)
            AIMealSuggestionsCard(vm: vm)
            WaterIntakeCard(vm: vm)
            MicronutrientsCard(vm: vm)
        }
        .task { await vm.refreshMealNote(store: store) }
    }
}

// MARK: - Macro Rings Card (concentric donut rings)

struct MacroRingsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false

    private struct Macro {
        let label: String; let current: Int; let target: Int
        let color: Color; let unit: String; let radius: CGFloat
    }

    private var macros: [Macro] {
        let stats = vm.healthStats
        return [
            Macro(label: "Carbs", current: Int(stats?.carbs ?? 0), target: 280, color: .steel, unit: "g", radius: 92),
            Macro(label: "Protein", current: Int(stats?.protein ?? 0), target: 180, color: .ember, unit: "g", radius: 68),
            Macro(label: "Fats", current: Int(stats?.fat ?? 0), target: 70, color: Color.amberLight, unit: "g", radius: 44),
        ]
    }

    private var totalCal: Int { vm.healthStats?.totalCalories ?? 0 }
    private var targetCal: Int { 2600 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TODAY'S MACROS")
                    .font(.forgeDynamic(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2.5)
                Spacer()
                Text("\(targetCal - totalCal) cal left")
                    .font(.forgeDynamic(size: 12, weight: .semibold))
                    .foregroundColor(.ember)
            }
            .padding(.bottom, 28)

            // Three concentric macro rings
            ZStack {
                ForEach(Array(macros.enumerated()), id: \.offset) { i, macro in
                    let progress = appeared ? CGFloat(macro.current) / CGFloat(macro.target) : 0

                    // Track
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)

                    // Glow
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(macro.color.opacity(0.3), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 7)

                    // Main
                    Circle()
                        .trim(from: 0, to: min(progress, 1))
                        .stroke(macro.color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .frame(width: macro.radius * 2, height: macro.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: macro.color.opacity(0.45), radius: 8)
                        .animation(.spring(response: 1.3, dampingFraction: 0.68).delay(0.25 + Double(i) * 0.15), value: appeared)
                }
                .accessibilityHidden(true)

                // Center: calorie total
                VStack(spacing: 2) {
                    Text("\(totalCal)")
                        .font(.forgeDynamic(size: 28, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("of \(targetCal) kcal")
                        .font(.forgeDynamic(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Calories")
                .accessibilityValue("\(totalCal) of \(targetCal) kcal")
            }
            .frame(height: 210)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)

            // Macro legend — responsive bars using GeometryReader (fixed hardcoded bug)
            VStack(spacing: 14) {
                ForEach(Array(macros.enumerated()), id: \.offset) { _, macro in
                    HStack(spacing: 12) {
                        Circle().fill(macro.color).frame(width: 8, height: 8)
                            .shadow(color: macro.color.opacity(0.5), radius: 3)
                        Text(macro.label)
                            .font(.forgeDynamic(size: 13, weight: .medium))
                            .foregroundColor(.textSecondary)
                            .frame(width: 52, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.3))
                                Capsule().fill(macro.color.opacity(0.8))
                                    .frame(width: appeared ? geo.size.width * CGFloat(macro.current) / CGFloat(macro.target) : 0)
                                    .animation(.spring(response: 1.1, dampingFraction: 0.7).delay(0.5), value: appeared)
                            }
                        }
                        .frame(height: 6)
                        Text("\(macro.current)\(macro.unit)")
                            .font(.forgeDynamic(size: 13, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .frame(width: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(macro.label)
                    .accessibilityValue("\(macro.current) of \(macro.target) \(macro.unit)")
                }
            }
        }
        .padding(24)
        .background(Color.surface)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

// MARK: - AI Nutrition Coach Card (fixed sparkle animation)

struct AINutritionCoachCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var tipIndex = 0
    @State private var sparkleScale: Double = 1.0
    @State private var appeared = false

    // Live ARIA insight overrides the local heuristic tip when present.
    private var liveInsight: String? { vm.aiNutritionInsight }

    private var tips: [(icon: String, color: Color, headline: String, body: String)] {
        guard let stats = vm.healthStats else {
            return [("sparkles", .ember, "Syncing nutrition data", "Connect HealthKit to unlock personalized macro coaching.")]
        }
        var generated: [(icon: String, color: Color, headline: String, body: String)] = []
        let proteinGap = max(0, Int(180 - stats.protein))
        if proteinGap > 0 {
            generated.append(("bolt.fill", .ember, "Protein gap — act before dinner", "You're \(proteinGap)g short today. Add lean protein to your next meal to hit 180g."))
        }
        if stats.water < 6 {
            generated.append(("drop.fill", .steel, "Hydration needs attention", "Only \(Int(stats.water)) of 8 glasses logged. Hydration supports recovery and energy."))
        } else {
            generated.append(("drop.fill", .steel, "Hydration is on track", "\(Int(stats.water)) of 8 glasses today. Keep sipping through the afternoon."))
        }
        if stats.sleepHours < 7 {
            generated.append(("moon.stars.fill", Color.violet, "Sleep is limiting recovery", "Last night: \(String(format: "%.1f", stats.sleepHours))h. Better sleep improves nutrient partitioning."))
        } else {
            generated.append(("moon.stars.fill", Color.violet, "Recovery window is strong", "Sleep and activity are aligned — great day to push training intensity."))
        }
        return generated
    }

    var tip: (icon: String, color: Color, headline: String, body: String) { tips[tipIndex % max(tips.count, 1)] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            coachHeader
            if appeared {
                coachInsightSection
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.ember.opacity(0.2), lineWidth: 1))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                sparkleScale = 1.25
            }
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }

    private var coachHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "sparkles")
                    .font(.forgeDynamic(size: 16, weight: .semibold))
                    .foregroundColor(.ember)
                    .scaleEffect(coachHeaderIconScale)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("AI Nutrition Coach").font(.forgeDynamic(size: 16, weight: .bold)).foregroundColor(.textPrimary)
                    if liveInsight != nil { coachBadge }
                }
                Text(coachSubtitle)
                    .font(.forgeDynamic(size: 11, weight: .medium)).foregroundColor(.textTertiary)
            }
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tipIndex += 1 }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.forgeDynamic(size: 13, weight: .semibold))
                    .foregroundColor(.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(Color.surfaceElevated)
                    .clipShape(Circle())
            }
            .opacity(liveInsight == nil ? 1 : 0.4)
            .disabled(liveInsight != nil)
        }
    }

    private var coachSubtitle: String {
        if vm.aiInsightsLoading { return "Consulting ARIA…" }
        if liveInsight != nil { return "Live insight" }
        return "Insight ready"
    }

    private var coachBadge: some View {
        Text(vm.aiInsightsLive ? "LIVE" : "ARIA")
            .font(.forgeDynamic(size: 8, weight: .black))
            .tracking(0.5)
            .foregroundColor(.ember)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.ember.opacity(0.12))
            .cornerRadius(5)
    }

    private var coachHeaderIconScale: CGFloat { vm.aiInsightsLoading ? sparkleScale : 1.0 }

    @ViewBuilder
    private var coachInsightSection: some View {
        Divider().background(Color.borderColor)
        tipDetailRow
        macroSnapshotChips
    }

    private var tipDetailRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: liveInsight != nil ? "sparkles" : tip.icon)
                .font(.forgeDynamic(size: 22))
                .foregroundColor(liveInsight != nil ? .ember : tip.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(liveInsight != nil ? "ARIA's take" : tip.headline)
                    .font(.forgeDynamic(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(liveInsight ?? tip.body)
                    .font(.forgeDynamic(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .id(liveInsight ?? "tip-\(tipIndex)")
    }

    private var macroSnapshotChips: some View {
        HStack(spacing: 0) {
            ForEach(macroSnapshots, id: \.label) { snapshot in
                VStack(spacing: 3) {
                    Text(snapshot.label)
                        .font(.forgeDynamic(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                    Text("\(snapshot.percent)%")
                        .font(.forgeDynamic(size: 13, weight: .bold))
                        .foregroundColor(snapshot.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(snapshot.color.opacity(0.08))
                if snapshot.label != "Cal" {
                    Divider().frame(height: 28).background(Color.borderColor)
                }
            }
        }
        .cornerRadius(12)
        .transition(.opacity)
    }

    private var macroSnapshots: [(label: String, percent: Int, color: Color)] {
        let stats = vm.healthStats
        return [
            ("Protein", min(Int((stats?.protein ?? 0) / 180 * 100), 100), Color.ember),
            ("Carbs", min(Int((stats?.carbs ?? 0) / 280 * 100), 100), Color.steel),
            ("Fats", min(Int((stats?.fat ?? 0) / 70 * 100), 100), Color.amberLight),
            ("Cal", min(Int(Double(stats?.totalCalories ?? 0) / 2600 * 100), 100), Color.violet),
        ]
    }
}

// MARK: - AI Meal Suggestions Card

struct AIMealSuggestionsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var setIndex = 0

    private var suggestions: [AIMealSuggestion] {
        let stats = vm.healthStats
        let proteinGap = max(0, Int(180 - (stats?.protein ?? 0)))
        let calRemaining = max(0, 2600 - (stats?.totalCalories ?? 0))

        let pool = popularRestaurants.flatMap { restaurant in
            restaurant.items.filter(\.isHealthy).map { item in
                AIMealSuggestion(
                    name: "\(restaurant.name) · \(item.name)",
                    cal: item.calories,
                    protein: item.protein,
                    carbs: item.carbs,
                    fat: item.fat,
                    reason: item.protein >= proteinGap
                        ? "Covers your \(proteinGap)g protein gap"
                        : "Fits your \(calRemaining) cal budget"
                )
            }
        }
        .sorted { $0.protein > $1.protein }

        if pool.isEmpty {
            return [
                AIMealSuggestion(name: "Grilled Chicken + Rice", cal: 480, protein: 42, carbs: 52, fat: 8, reason: "High-protein recovery meal"),
                AIMealSuggestion(name: "Greek Yogurt Parfait", cal: 320, protein: 28, carbs: 38, fat: 6, reason: "Light protein boost"),
            ]
        }

        let start = (setIndex * 3) % pool.count
        return Array(pool[start..<min(start + 3, pool.count)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle.fill").font(.forgeDynamic(size: 20)).foregroundColor(.steel)
                    Text("AI Meal Suggestions").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { setIndex += 1 }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.forgeDynamic(size: 10))
                        Text("Regenerate").font(.forgeDynamic(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.steel)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.steel.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            Text("Based on \(max(0, 2600 - (vm.healthStats?.totalCalories ?? 0))) cal · \(max(0, Int(180 - (vm.healthStats?.protein ?? 0))))g protein remaining")
                .font(.forgeDynamic(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            if let note = vm.aiMealNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").font(.forgeDynamic(size: 11)).foregroundColor(.steel)
                    Text(note)
                        .font(.forgeDynamic(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.steel.opacity(0.08))
                .cornerRadius(10)
            }

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    AIMealRow(suggestion: suggestion)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .id("\(setIndex)-\(suggestion.id)")
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

struct AIMealSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let cal: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let reason: String
}

struct AIMealRow: View {
    let suggestion: AIMealSuggestion
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(suggestion.name).font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary)
                        Text(suggestion.reason).font(.forgeDynamic(size: 11)).foregroundColor(.textTertiary).lineLimit(1)
                    }
                    Spacer()
                    Text("\(suggestion.cal) cal")
                        .font(.forgeDynamic(size: 13, weight: .bold)).foregroundColor(.ember)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.forgeDynamic(size: 11, weight: .semibold)).foregroundColor(.textMuted)
                }
                .padding(13)
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 0) {
                    InlineMacroChip(label: "P", value: "\(suggestion.protein)g", color: .ember)
                    InlineMacroChip(label: "C", value: "\(suggestion.carbs)g",   color: .steel)
                    InlineMacroChip(label: "F", value: "\(suggestion.fat)g",     color: Color.amberLight)
                }
                .padding(.horizontal, 13).padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

struct InlineMacroChip: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.forgeDynamic(size: 10, weight: .bold)).foregroundColor(.textTertiary)
            Text(value).font(.forgeDynamic(size: 13, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(color.opacity(0.09)).cornerRadius(8)
    }
}

// MARK: - Meal Log Card

// MARK: - Barcode Meal Logging

/// Nutrition lookup backed by the free Open Food Facts API (no key required).
enum FoodLookup {
    struct Result: Identifiable {
        let id = UUID()
        let found: Bool
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    static func lookup(barcode: String) async -> Result {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,nutriments"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any]
        else {
            return Result(found: false, name: "", calories: 0, protein: 0, carbs: 0, fat: 0)
        }

        let nutriments = (product["nutriments"] as? [String: Any]) ?? [:]
        func number(_ keys: [String]) -> Double {
            for key in keys {
                if let v = nutriments[key] as? Double { return v }
                if let v = nutriments[key] as? Int { return Double(v) }
                if let s = nutriments[key] as? String, let v = Double(s) { return v }
            }
            return 0
        }

        let name = (product["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Scanned item"
        // Prefer per-serving values; fall back to per-100g.
        return Result(
            found: true,
            name: name,
            calories: number(["energy-kcal_serving", "energy-kcal_100g", "energy-kcal"]),
            protein: number(["proteins_serving", "proteins_100g", "proteins"]),
            carbs: number(["carbohydrates_serving", "carbohydrates_100g", "carbohydrates"]),
            fat: number(["fat_serving", "fat_100g", "fat"])
        )
    }
}

/// Live camera barcode scanner (EAN/UPC) wrapping AVFoundation.
struct BarcodeScannerView: UIViewControllerRepresentable {
    var onScan: (String) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.onScan = onScan
        vc.onCancel = onCancel
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScan: ((String) -> Void)?
        var onCancel: (() -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var didScan = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black

            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.layer.bounds
            view.layer.addSublayer(layer)
            preview = layer

            let cancel = UIButton(type: .system)
            cancel.setTitle("Cancel", for: .normal)
            cancel.setTitleColor(.white, for: .normal)
            cancel.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            cancel.translatesAutoresizingMaskIntoConstraints = false
            cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            view.addSubview(cancel)
            NSLayoutConstraint.activate([
                cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            ])
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.layer.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        @objc private func cancelTapped() { onCancel?() }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !didScan,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let code = object.stringValue else { return }
            didScan = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onScan?(code)
        }
    }
}

/// Confirmation shown after a barcode scan resolves (or fails) before logging.
struct ScannedFoodConfirmSheet: View {
    let food: FoodLookup.Result
    var onLog: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Color.borderColor).frame(width: 40, height: 5).padding(.top, 10)

            if food.found {
                Image(systemName: "checkmark.seal.fill").font(.forgeDynamic(size: 40)).foregroundColor(.success)
                Text(food.name)
                    .font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center).padding(.horizontal, 20)

                HStack(spacing: 10) {
                    macroPill("Cal", "\(Int(food.calories))", .ember)
                    macroPill("Protein", "\(Int(food.protein))g", .steel)
                    macroPill("Carbs", "\(Int(food.carbs))g", Color.violet)
                    macroPill("Fat", "\(Int(food.fat))g", Color.amberLight)
                }
                .padding(.horizontal, 20)

                Button(action: onLog) {
                    Text("Log Meal").font(.forgeDynamic(size: 16, weight: .bold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.ember).cornerRadius(14)
                }
                .padding(.horizontal, 20)
            } else {
                Image(systemName: "barcode.viewfinder").font(.forgeDynamic(size: 40)).foregroundColor(.textTertiary)
                Text("No nutrition data found").font(.forgeDynamic(size: 17, weight: .semibold)).foregroundColor(.textPrimary)
                Text("We couldn't match that barcode. Try another product or log it manually.")
                    .font(.forgeDynamic(size: 13)).foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
            }

            Button("Close", action: onDismiss)
                .font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textTertiary)
                .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
    }

    private func macroPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.forgeDynamic(size: 15, weight: .bold)).foregroundColor(color)
            Text(label).font(.forgeDynamic(size: 10, weight: .semibold)).foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08))
        .cornerRadius(10)
    }
}

// MARK: - Meal Log Card

struct MealLogCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var showScanner = false
    @State private var scanResult: FoodLookup.Result?
    @State private var isLookingUp = false

    private func mealIcon(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return "sunrise.fill"
        case 11..<15: return "sun.max.fill"
        case 15..<17: return "leaf.fill"
        default: return "moon.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Meal Log").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("\(vm.loggedMeals.count) logged")
                    .font(.forgeDynamic(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
                Button { showScanner = true } label: {
                    HStack(spacing: 5) {
                        if isLookingUp {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "barcode.viewfinder").font(.forgeDynamic(size: 13, weight: .semibold))
                        }
                        Text("Scan").font(.forgeDynamic(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.ember)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.ember.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(isLookingUp)
            }

            if vm.loggedMeals.isEmpty {
                Text("No meals logged yet today. Use Quick Location Log or Restaurants to add your first meal.")
                    .font(.forgeDynamic(size: 13))
                    .foregroundColor(.textSecondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceElevated)
                    .cornerRadius(12)
            } else {
                VStack(spacing: 10) {
                    ForEach(vm.loggedMeals.sorted(by: { $0.date > $1.date })) { meal in
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.surface).frame(width: 38, height: 38)
                                Image(systemName: mealIcon(for: meal.date))
                                    .font(.forgeDynamic(size: 15)).foregroundColor(.ember)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(meal.name).font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(1)
                                Text(meal.date, format: .dateTime.hour().minute())
                                    .font(.forgeDynamic(size: 12)).foregroundColor(.textTertiary)
                            }
                            Spacer()
                            Text("\(Int(meal.calories)) cal")
                                .font(.forgeDynamic(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.forgeDynamic(size: 18)).foregroundColor(.success)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.surfaceElevated).cornerRadius(12)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        .sheet(isPresented: $showScanner) {
            BarcodeScannerView(
                onScan: { code in
                    showScanner = false
                    Task {
                        isLookingUp = true
                        scanResult = await FoodLookup.lookup(barcode: code)
                        isLookingUp = false
                    }
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: $scanResult) { food in
            ScannedFoodConfirmSheet(food: food) {
                Task {
                    await vm.logMeal(name: food.name, calories: food.calories, protein: food.protein, carbs: food.carbs, fat: food.fat)
                    scanResult = nil
                }
            } onDismiss: {
                scanResult = nil
            }
        }
    }
}

// MARK: - Water Intake Card (HealthKit Integration)

struct WaterIntakeCard: View {
    @ObservedObject var vm: LifestyleViewModel
    let target = 8

    private var consumed: Int { Int(vm.healthStats?.water ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "drop.fill")
                        .font(.forgeDynamic(size: 16)).foregroundColor(Color(hex: "4A9EFF"))
                    Text("Water Intake").font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)
                }
                Spacer()
                Text("\(consumed)/\(target)")
                    .font(.forgeDynamic(size: 14, weight: .bold)).foregroundColor(Color(hex: "4A9EFF"))
            }

            HStack(spacing: 8) {
                ForEach(0..<target, id: \.self) { i in
                    Image(systemName: i < consumed ? "drop.fill" : "drop")
                        .foregroundColor(i < consumed ? Color(hex: "4A9EFF") : Color.borderColor)
                        .font(.forgeDynamic(size: 22))
                        .scaleEffect(i < consumed ? 1 : 0.85)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6).delay(Double(i) * 0.03), value: consumed)
                }
            }

            Button {
                guard consumed < target else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await vm.logWater(glasses: 1) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.forgeDynamic(size: 15))
                    Text("Log a glass").font(.forgeDynamic(size: 14, weight: .semibold))
                    Spacer()
                    Text("Syncs with HealthKit")
                        .font(.forgeDynamic(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "4A9EFF").opacity(0.7))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(hex: "4A9EFF").opacity(0.1))
                        .cornerRadius(4)
                }
                .foregroundColor(Color(hex: "4A9EFF"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(hex: "4A9EFF").opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
    }
}

// MARK: - Micronutrients Card (fixed: now animates on appear)

struct MicronutrientsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false

    private var micros: [(label: String, current: Double, target: Double, unit: String, color: Color)] {
        let stats = vm.healthStats
        return [
            ("Fiber", stats?.fiber ?? 0, 30, "g", .success),
            ("Sugar", stats?.sugar ?? 0, 50, "g", .warning),
            ("Sodium", stats?.sodium ?? 0, 2300, "mg", .steel),
            ("Caffeine", stats?.caffeine ?? 0, 400, "mg", .ember),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Micronutrients")
                .font(.forgeDynamic(size: 18, weight: .bold)).foregroundColor(.textPrimary)

            VStack(spacing: 14) {
                ForEach(Array(micros.enumerated()), id: \.offset) { i, m in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(m.label).font(.forgeDynamic(size: 13, weight: .medium)).foregroundColor(.textSecondary)
                            Spacer()
                            Text(m.current < 10
                                 ? String(format: "%.1f / %.1f %@", m.current, m.target, m.unit)
                                 : "\(Int(m.current)) / \(Int(m.target)) \(m.unit)")
                                .font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textPrimary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.borderColor.opacity(0.3))
                                Capsule().fill(m.color)
                                    .frame(width: appeared ? geo.size.width * CGFloat(min(m.current / m.target, 1)) : 0)
                                    // Fixed: now animated
                                    .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.3 + Double(i) * 0.1), value: appeared)
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 14, y: 5)
        .onAppear { appeared = true }
    }
}

// MARK: - Restaurant Nutrition Database

struct NutritionDatabaseView: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var selectedCategory: RestaurantCategory = .all
    @State private var searchText = ""
    @State private var selectedRestaurant: Restaurant?
    @State private var appeared = false

    var filtered: [Restaurant] {
        let base = selectedCategory == .all ? popularRestaurants : popularRestaurants.filter { $0.category == selectedCategory }
        if searchText.isEmpty { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.items.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Search
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(.textTertiary)
                TextField("Search restaurants or items…", text: $searchText)
                    .foregroundColor(.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.textMuted)
                    }
                }
            }
            .padding(13)
            .background(Color.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))

            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RestaurantCategory.allCases, id: \.self) { cat in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedCategory = cat }
                        } label: {
                            Text(cat.rawValue)
                                .font(.forgeDynamic(size: 13, weight: .semibold))
                                .foregroundColor(selectedCategory == cat ? .white : .textTertiary)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(
                                    selectedCategory == cat
                                        ? Color.ember : Color.surface.opacity(0.7)
                                )
                                .cornerRadius(20)
                        }
                    }
                }
            }

            AIBestPicksSection(vm: vm)

            // Restaurant grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { i, restaurant in
                    Button { selectedRestaurant = restaurant } label: {
                        RestaurantCard(restaurant: restaurant)
                    }
                    .buttonStyle(.plain)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.05 + Double(i) * 0.04), value: appeared)
                }
            }
        }
        .sheet(item: $selectedRestaurant) { r in
            RestaurantMenuSheet(restaurant: r, vm: vm)
        }
        .onAppear { appeared = true }
        .task { await vm.refreshBestPicksNote(store: store) }
    }
}

struct RestaurantCard: View {
    let restaurant: Restaurant

    private var avgProteinEfficiency: Int {
        let scores = restaurant.items.map { $0.proteinEfficiency }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
    }

    private var efficiencyColor: Color {
        switch avgProteinEfficiency {
        case 100...: return .success
        case 60..<100: return .warning
        default: return .danger
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(restaurant.logo)
                .font(.forgeDynamic(size: 44))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Text(restaurant.name)
                .font(.forgeDynamic(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text("\(restaurant.items.count) items")
                    .font(.forgeDynamic(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                // Protein efficiency rating
                Text(NutritionRating(proteinEfficiency: avgProteinEfficiency).label)
                    .font(.forgeDynamic(size: 11, weight: .semibold))
                    .foregroundColor(efficiencyColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.surface)
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.borderColor.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension NutritionRating {
    init(proteinEfficiency: Int) {
        switch proteinEfficiency {
        case 100...: self = .excellent
        case 60..<100: self = .good
        case 30..<60: self = .fair
        default: self = .poor
        }
    }
}

// MARK: - Restaurant Menu Sheet (fixed: NavigationStack replacing deprecated NavigationView)

struct RestaurantMenuSheet: View {
    let restaurant: Restaurant
    @ObservedObject var vm: LifestyleViewModel
    @State private var sortBy: MenuSort = .calories
    @State private var loggedItemID: UUID?
    @Environment(\.dismiss) private var dismiss

    enum MenuSort: String, CaseIterable {
        case calories = "Calories", protein = "Protein", name = "Name", healthy = "Healthiest"
    }

    var sorted: [MenuItem] {
        switch sortBy {
        case .calories: return restaurant.items.sorted { $0.calories < $1.calories }
        case .protein:  return restaurant.items.sorted { $0.protein > $1.protein }
        case .name:     return restaurant.items.sorted { $0.name < $1.name }
        case .healthy:  return restaurant.items.sorted { $0.proteinEfficiency > $1.proteinEfficiency }
        }
    }

    var body: some View {
        // Fixed: NavigationView → NavigationStack
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Hero header
                    HStack(spacing: 16) {
                        Text(restaurant.logo).font(.forgeDynamic(size: 48))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(restaurant.name)
                                .font(.forgeDynamic(size: 24, weight: .bold))
                                .foregroundColor(.textPrimary)
                            Text("\(restaurant.items.count) menu items")
                                .font(.forgeDynamic(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(20)
                    .background(Color.surface)
                    .overlay(Rectangle().fill(Color.borderColor.opacity(0.4)).frame(height: 1), alignment: .bottom)

                    Picker("Sort", selection: $sortBy) {
                        ForEach(MenuSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20).padding(.vertical, 14)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(sorted) { item in
                                MenuItemCard(item: item, isLogged: loggedItemID == item.id) {
                                    Task {
                                        await vm.logMeal(
                                            name: "\(restaurant.name) - \(item.name)",
                                            calories: Double(item.calories),
                                            protein: Double(item.protein),
                                            carbs: Double(item.carbs),
                                            fat: Double(item.fat)
                                        )
                                        loggedItemID = item.id
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20).padding(.bottom, 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.ember).fontWeight(.semibold)
                }
            }
        }
    }
}

struct MenuItemCard: View {
    let item: MenuItem
    var isLogged: Bool = false
    var onLog: (() -> Void)? = nil
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.forgeDynamic(size: 15, weight: .semibold)).foregroundColor(.textPrimary)
                    Text(item.serving)
                        .font(.forgeDynamic(size: 11, weight: .medium)).foregroundColor(.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if item.isHealthy {
                        Image(systemName: "leaf.fill")
                            .font(.forgeDynamic(size: 13)).foregroundColor(.success)
                    }
                    Text(item.nutritionalRating.label)
                        .font(.forgeDynamic(size: 10, weight: .bold))
                        .foregroundColor(item.nutritionalRating.color)
                }
            }

            Divider().background(Color.borderColor.opacity(0.4))

            HStack(spacing: 10) {
                MacroChip(label: "Cal",  value: "\(item.calories)",  color: .ember)
                MacroChip(label: "Prot", value: "\(item.protein)g",  color: .steel)
                MacroChip(label: "Carb", value: "\(item.carbs)g",    color: Color.amberLight)
                MacroChip(label: "Fat",  value: "\(item.fat)g",      color: Color.violet)
            }

            if let onLog {
                Button(action: onLog) {
                    HStack(spacing: 6) {
                        Image(systemName: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                        Text(isLogged ? "Logged to HealthKit" : "Log Meal")
                            .font(.forgeDynamic(size: 13, weight: .semibold))
                    }
                    .foregroundColor(isLogged ? .success : .ember)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background((isLogged ? Color.success : Color.ember).opacity(0.12))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isLogged)
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(14)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75).delay(0.05)) { appeared = true }
        }
    }
}

struct MacroChip: View {
    let label: String; let value: String; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.forgeDynamic(size: 9, weight: .bold)).foregroundColor(.textTertiary)
            Text(value).font(.forgeDynamic(size: 13, weight: .bold)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(9)
    }
}

// MARK: - AI Best Picks

struct AIBestPicksSection: View {
    @ObservedObject var vm: LifestyleViewModel

    private var picks: [AIRestaurantPick] {
        let proteinGap = max(0, Int(180 - (vm.healthStats?.protein ?? 0)))
        return popularRestaurants.flatMap { restaurant in
            restaurant.items.filter(\.isHealthy).map { item in
                AIRestaurantPick(
                    restaurant: restaurant.name,
                    emoji: restaurant.logo,
                    item: item.name,
                    cal: item.calories,
                    protein: item.protein,
                    reason: item.protein >= proteinGap
                        ? "Best protein efficiency for your \(proteinGap)g gap"
                        : "High protein, fits remaining calories"
                )
            }
        }
        .sorted { $0.protein > $1.protein }
        .prefix(3)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.forgeDynamic(size: 14, weight: .semibold)).foregroundColor(.ember)
                Text("AI Best Picks for Today").font(.forgeDynamic(size: 15, weight: .bold)).foregroundColor(.textPrimary)
                Spacer()
                Text("\(max(0, Int(180 - (vm.healthStats?.protein ?? 0))))g protein left")
                    .font(.forgeDynamic(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
            }

            // Live ARIA coaching note over the protein-ranked picks (fallback: none).
            if let note = vm.aiBestPicksNote {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles").font(.forgeDynamic(size: 11)).foregroundColor(.ember)
                    Text(note)
                        .font(.forgeDynamic(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ember.opacity(0.06))
                .cornerRadius(10)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(picks) { pick in
                        AIPickCard(pick: pick)
                    }
                }
            }
        }
        .padding(16)
        .background(LinearGradient(colors: [Color.ember.opacity(0.07), Color.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(18)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.ember.opacity(0.18), lineWidth: 1))
    }
}

struct AIRestaurantPick: Identifiable {
    let id = UUID()
    let restaurant: String; let emoji: String; let item: String
    let cal: Int; let protein: Int; let reason: String
}

struct AIPickCard: View {
    let pick: AIRestaurantPick

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(pick.emoji).font(.forgeDynamic(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.restaurant).font(.forgeDynamic(size: 10, weight: .bold)).foregroundColor(.textTertiary)
                    Text(pick.item).font(.forgeDynamic(size: 13, weight: .semibold)).foregroundColor(.textPrimary).lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                Label("\(pick.cal) cal", systemImage: "flame.fill").font(.forgeDynamic(size: 11, weight: .semibold)).foregroundColor(.ember)
                Label("\(pick.protein)g P", systemImage: "bolt.fill").font(.forgeDynamic(size: 11, weight: .semibold)).foregroundColor(.steel)
            }
            Text(pick.reason).font(.forgeDynamic(size: 10, weight: .medium)).foregroundColor(.textTertiary).lineLimit(2)
        }
        .frame(width: 180)
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ember.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }
}

