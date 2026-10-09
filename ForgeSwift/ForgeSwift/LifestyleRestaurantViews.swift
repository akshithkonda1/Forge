import SwiftUI
import AVFoundation
import UIKit
import ForgeCore

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
        VStack(spacing: FDS.Spacing.lg) {
            Capsule().fill(Color.borderColor).frame(width: 40, height: 5).padding(.top, FDS.Spacing.md)

            if food.found {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundColor(.success)
                Text(food.name)
                    .font(FDS.TypeScale.Dynamic.headline).foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center).padding(.horizontal, FDS.Spacing.lg)

                HStack(spacing: FDS.Spacing.md) {
                    macroPill("Cal", "\(Int(food.calories))", .ember)
                    macroPill("Protein", "\(Int(food.protein))g", .steel)
                    macroPill("Carbs", "\(Int(food.carbs))g", Color.aurora)
                    macroPill("Fat", "\(Int(food.fat))g", Color.amber)
                }
                .padding(.horizontal, FDS.Spacing.lg)

                Button(action: onLog) {
                    Text("Log Meal").font(FDS.TypeScale.Dynamic.headline).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, FDS.Spacing.lg)
                        .background(Color.ember).cornerRadius(FDS.Radius.md)
                }
                .padding(.horizontal, FDS.Spacing.lg)
            } else {
                Image(systemName: "barcode.viewfinder").font(.system(size: 40)).foregroundColor(.textTertiary)
                Text("No nutrition data found").font(FDS.TypeScale.Dynamic.headline).foregroundColor(.textPrimary)
                Text("We couldn't match that barcode. Try another product or log it manually.")
                    .font(.system(size: 13)).foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 30)
            }

            Button("Close", action: onDismiss)
                .font(.system(size: 14, weight: .semibold)).foregroundColor(.textTertiary)
                .padding(.bottom, FDS.Spacing.lg)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium])
    }

    private func macroPill(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value).font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(color)
            Text(label).font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FDS.Spacing.md)
        .background(color.opacity(0.08))
        .cornerRadius(FDS.Radius.sm)
    }
}

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
        VStack(spacing: FDS.Spacing.lg) {
            // Search
            HStack(spacing: FDS.Spacing.md) {
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
            .padding(FDS.Spacing.md)
            .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: .amber)

            // Category pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FDS.Spacing.sm) {
                    ForEach(RestaurantCategory.allCases, id: \.self) { cat in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selectedCategory = cat }
                        } label: {
                            Text(cat.rawValue)
                                .font(FDS.TypeScale.Dynamic.caption)
                                .foregroundColor(selectedCategory == cat ? .white : .textTertiary)
                                .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.sm)
                                .background(
                                    selectedCategory == cat
                                        ? Color.ember : Color.surface.opacity(0.7)
                                )
                                .cornerRadius(FDS.Radius.xl)
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
        VStack(spacing: FDS.Spacing.md) {
            Text(restaurant.logo)
                .font(.system(size: 44))
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            Text(restaurant.name)
                .font(FDS.TypeScale.Dynamic.body.weight(.semibold))
                .foregroundColor(.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: FDS.Spacing.sm) {
                Text("\(restaurant.items.count) items")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundColor(.textTertiary)
                Circle().fill(Color.borderColor).frame(width: 3, height: 3)
                // Protein efficiency rating
                Text(NutritionRating(proteinEfficiency: avgProteinEfficiency).label)
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundColor(efficiencyColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.lg, accent: .amber)
    }
}

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
                    HStack(spacing: FDS.Spacing.lg) {
                        Text(restaurant.logo).font(.system(size: 48))
                        VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                            Text(restaurant.name)
                                .font(FDS.TypeScale.Dynamic.title)
                                .foregroundColor(.textPrimary)
                            Text("\(restaurant.items.count) menu items")
                                .font(FDS.TypeScale.Dynamic.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(FDS.Spacing.lg)
                    .background(Color.surface)
                    .overlay(Rectangle().fill(Color.borderColor.opacity(0.4)).frame(height: 1), alignment: .bottom)

                    Picker("Sort", selection: $sortBy) {
                        ForEach(MenuSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, FDS.Spacing.lg).padding(.vertical, FDS.Spacing.lg)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: FDS.Spacing.md) {
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
                        .padding(.horizontal, FDS.Spacing.lg).padding(.bottom, 40)
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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: FDS.Spacing.xs) {
                    Text(item.name)
                        .font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
                    Text(item.serving)
                        .font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: FDS.Spacing.xs) {
                    if item.isHealthy {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 13)).foregroundColor(.success)
                    }
                    Text(item.nutritionalRating.label)
                        .font(FDS.TypeScale.Dynamic.micro)
                        .foregroundColor(item.nutritionalRating.color)
                }
            }

            Divider().background(Color.borderColor.opacity(0.4))

            HStack(spacing: FDS.Spacing.md) {
                MacroChip(label: "Cal",  value: "\(item.calories)",  color: .ember)
                MacroChip(label: "Prot", value: "\(item.protein)g",  color: .steel)
                MacroChip(label: "Carb", value: "\(item.carbs)g",    color: Color.amber)
                MacroChip(label: "Fat",  value: "\(item.fat)g",      color: Color.aurora)
            }

            if let onLog {
                Button(action: onLog) {
                    HStack(spacing: FDS.Spacing.sm) {
                        Image(systemName: isLogged ? "checkmark.circle.fill" : "plus.circle.fill")
                        Text(isLogged ? "Logged to Apple Health" : "Log Meal")
                            .font(FDS.TypeScale.Dynamic.caption)
                    }
                    .foregroundColor(isLogged ? .success : .ember)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FDS.Spacing.md)
                    .background((isLogged ? Color.success : Color.ember).opacity(0.12))
                    .cornerRadius(FDS.Radius.sm)
                }
                .buttonStyle(.plain)
                .disabled(isLogged)
            }
        }
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: .amber)
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
        VStack(spacing: FDS.Spacing.xs) {
            Text(label).font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textTertiary)
            Text(value).font(FDS.TypeScale.Dynamic.caption).foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, FDS.Spacing.sm)
        .background(color.opacity(0.1))
        .cornerRadius(FDS.Radius.sm)
    }
}

struct AIBestPicksSection: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore

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
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundColor(.ember)
                Text("AI Best Picks for Today").font(FDS.TypeScale.Dynamic.body.weight(.semibold)).foregroundColor(.textPrimary)
                Spacer()
                Text("\(max(0, Int(180 - (vm.healthStats?.protein ?? 0))))g protein left")
                    .font(FDS.TypeScale.Dynamic.micro)
                    .foregroundColor(.textTertiary)
            }

            // Live ARIA coaching note over the protein-ranked picks (fallback: none).
            if let note = vm.aiBestPicksNote {
                HStack(alignment: .top, spacing: FDS.Spacing.sm) {
                    ARIAIdentityMark(state: .idle, mood: .energized, size: 14, amplitude: 0.22)
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(FDS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ember.opacity(0.06))
                .cornerRadius(FDS.Radius.sm)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: FDS.Spacing.md) {
                    ForEach(picks) { pick in
                        AIPickCard(pick: pick)
                    }
                }
            }
        }
        .padding(FDS.Spacing.lg)
        .background(LinearGradient(colors: [Color.ember.opacity(0.07), Color.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        .cornerRadius(FDS.Radius.lg)
        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.lg).stroke(Color.ember.opacity(0.18), lineWidth: 1))
        .task { await vm.refreshBestPicksNote(store: store) }
    }
}

struct AIPickCard: View {
    let pick: AIRestaurantPick

    var body: some View {
        VStack(alignment: .leading, spacing: FDS.Spacing.md) {
            HStack(spacing: FDS.Spacing.sm) {
                Text(pick.emoji).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.restaurant).font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textTertiary)
                    Text(pick.item).font(FDS.TypeScale.Dynamic.caption).foregroundColor(.textPrimary).lineLimit(2)
                }
            }
            HStack(spacing: FDS.Spacing.sm) {
                Label("\(pick.cal) cal", systemImage: "flame.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(.ember)
                Label("\(pick.protein)g P", systemImage: "bolt.fill").font(.system(size: 11, weight: .semibold)).foregroundColor(.steel)
            }
            Text(pick.reason).font(FDS.TypeScale.Dynamic.micro).foregroundColor(.textTertiary).lineLimit(2)
        }
        .frame(width: 180)
        .padding(FDS.Spacing.lg)
        .forgeGlassCard(cornerRadius: FDS.Radius.md, accent: .ember)
    }
}
