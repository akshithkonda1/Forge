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
            cancel.accessibilityLabel = "Cancel"
            cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            view.addSubview(cancel)
            NSLayoutConstraint.activate([
                cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
                cancel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
                cancel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
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
            ForgeHaptics.play(.success)
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
        ScrollView {
            VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                ForgeSheetHeader(
                    title: food.found ? food.name : "No nutrition data found",
                    closeLabel: "Close",
                    onClose: onDismiss
                )
                if food.found {
                    foundContent
                } else {
                    notFoundContent
                }
            }
            .forgeScreenInsets(top: FDS.Spacing.lg)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var foundContent: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
            ForgeStatGrid(columns: 4) {
                ForgeStatTile(label: "Cal", value: "\(Int(food.calories))", energy: FoodMacroPalette.calories)
                ForgeStatTile(label: "Protein", value: "\(Int(food.protein))", unit: "g", energy: FoodMacroPalette.protein)
                ForgeStatTile(label: "Carbs", value: "\(Int(food.carbs))", unit: "g", energy: FoodMacroPalette.carbs)
                ForgeStatTile(label: "Fat", value: "\(Int(food.fat))", unit: "g", energy: FoodMacroPalette.fat)
            }
            .forgeContentCard(tint: .amber)

            ForgePrimaryButton(title: "Log Meal", action: onLog)
        }
    }

    private var notFoundContent: some View {
        VStack(spacing: ForgeLayout.blockGap) {
            ForgeIconWell(systemImage: "barcode.viewfinder", tint: .textTertiary, diameter: 56)
            Text("We couldn't match that barcode. Try another product or log it manually.")
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, FDS.Spacing.xl)
                .forgeWrapping()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Restaurant browser

struct NutritionDatabaseView: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore
    @State private var selectedCategory: RestaurantCategory = .all
    @State private var searchText = ""
    @State private var selectedRestaurant: Restaurant?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var filtered: [Restaurant] {
        let base = selectedCategory == .all ? popularRestaurants : popularRestaurants.filter { $0.category == selectedCategory }
        if searchText.isEmpty { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.items.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var categoryOptions: [ForgeSegmentOption<RestaurantCategory>] {
        RestaurantCategory.allCases.map { ForgeSegmentOption(value: $0, title: $0.rawValue) }
    }

    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [
            GridItem(.flexible(), spacing: FDS.Spacing.md),
            GridItem(.flexible(), spacing: FDS.Spacing.md),
        ]
    }

    var body: some View {
        VStack(spacing: ForgeLayout.sectionGap) {
            searchField

            ForgeSegmentedControl(categoryOptions, selection: $selectedCategory, accent: .amber)

            AIBestPicksSection(vm: vm)

            LazyVGrid(columns: gridColumns, spacing: FDS.Spacing.md) {
                ForEach(filtered) { restaurant in
                    Button { selectedRestaurant = restaurant } label: {
                        RestaurantCard(restaurant: restaurant)
                    }
                    .buttonStyle(ForgePressStyle())
                    .accessibilityHint("Opens the menu")
                }
            }
        }
        .sheet(item: $selectedRestaurant) { r in
            RestaurantMenuSheet(restaurant: r, vm: vm)
        }
    }

    private var searchField: some View {
        HStack(spacing: FDS.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            TextField("Search restaurants or items…", text: $searchText)
                .font(HomeType.body)
                .foregroundStyle(Color.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.textMuted)
                        .frame(width: ForgeUX.minTap, height: ForgeUX.minTap)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, FDS.Spacing.md)
        .frame(minHeight: ForgeUX.minTap)
        .forgeInsetTile(radius: ForgeLayout.innerRadius)
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
        case 100...: return Color.vitality
        case 60..<100: return Color.amber
        default: return HudChrome.miss
        }
    }

    private var ratingLabel: String {
        NutritionRating(proteinEfficiency: avgProteinEfficiency).label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            Text(restaurant.logo)
                .font(.system(size: 44))
                .accessibilityHidden(true)

            Text(restaurant.name)
                .font(HomeType.status)
                .foregroundStyle(Color.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            ForgeAdaptiveStack(spacing: ForgeLayout.chipGap, alignment: .firstTextBaseline) {
                Text("\(restaurant.items.count) items")
                    .foregroundStyle(Color.textTertiary)
                Text(ratingLabel)
                    .foregroundStyle(efficiencyColor)
            }
            .font(HomeType.micro)
        }
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: .infinity, alignment: .topLeading)
        .forgeContentCard(padding: ForgeLayout.compactCardPadding)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Menu sheet

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

    private var sortOptions: [ForgeSegmentOption<MenuSort>] {
        MenuSort.allCases.map { ForgeSegmentOption(value: $0, title: $0.rawValue) }
    }

    var body: some View {
        // Fixed: NavigationView → NavigationStack
        NavigationStack {
            ZStack {
                Color.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ForgeLayout.sectionGap) {
                        sheetHero
                        ForgeSegmentedControl(sortOptions, selection: $sortBy, accent: .amber)
                        menuList
                    }
                    .forgeScreenInsets(top: FDS.Spacing.lg)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Color.ember).fontWeight(.semibold)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var sheetHero: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap) {
            Text(restaurant.logo)
                .font(.system(size: 48))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(restaurant.name)
                    .font(ForgeType.title)
                    .foregroundStyle(Color.textPrimary)
                    .forgeWrapping()
                    .accessibilityAddTraits(.isHeader)
                Text("\(restaurant.items.count) menu items")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var menuList: some View {
        LazyVStack(spacing: ForgeLayout.sectionGap) {
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
                        ForgeHaptics.play(.success)
                    }
                }
            }
        }
    }
}

struct MenuItemCard: View {
    let item: MenuItem
    var isLogged: Bool = false
    var onLog: (() -> Void)? = nil

    private var ratingColor: Color {
        switch item.nutritionalRating {
        case .excellent: return Color.vitality
        case .good: return Color.steel
        case .fair: return Color.amber
        case .poor: return HudChrome.miss
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            header

            ForgeStatGrid(columns: 4, minCellWidth: 64) {
                MacroChip(label: "Cal", value: "\(item.calories)", color: FoodMacroPalette.calories)
                MacroChip(label: "Protein", value: "\(item.protein)g", color: FoodMacroPalette.protein)
                MacroChip(label: "Carbs", value: "\(item.carbs)g", color: FoodMacroPalette.carbs)
                MacroChip(label: "Fat", value: "\(item.fat)g", color: FoodMacroPalette.fat)
            }

            if let onLog {
                footer(onLog)
            }
        }
        .forgeContentCard(tint: .amber)
    }

    private var header: some View {
        ForgeAdaptiveStack(spacing: ForgeLayout.rowGap, alignment: .top) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Text(item.name)
                    .font(HomeType.status)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                Text(item.serving)
                    .font(HomeType.micro)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            HStack(spacing: ForgeLayout.chipGap) {
                if item.isHealthy {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.vitality)
                        .accessibilityLabel("Healthy choice")
                }
                HudVibeChip(label: item.nutritionalRating.label, energy: ratingColor)
            }
        }
    }

    @ViewBuilder
    private func footer(_ onLog: @escaping () -> Void) -> some View {
        if isLogged {
            HStack(spacing: FDS.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: ForgeUX.icon, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Logged to Apple Health")
                    .font(HomeType.label)
                    .forgeSingleLine(minScale: ForgeLayout.labelMinScale)
            }
            .foregroundStyle(Color.vitality)
            .frame(maxWidth: .infinity, minHeight: ForgeUX.minTap)
            .background(Color.vitality.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: FDS.Radius.md, style: .continuous)
                    .stroke(Color.vitality.opacity(0.28), lineWidth: ForgeUX.hairline)
            )
            .accessibilityElement(children: .combine)
        } else {
            ForgeSecondaryButton(title: "Log Meal", icon: "plus", accent: .ember, action: onLog)
        }
    }
}

struct MacroChip: View {
    let label: String; let value: String; let color: Color

    private var unit: String? { value.hasSuffix("g") ? "g" : nil }
    private var number: String { value.hasSuffix("g") ? String(value.dropLast()) : value }

    var body: some View {
        ForgeStatTile(label: label, value: number, unit: unit, energy: color)
    }
}

// MARK: - Best picks

struct AIBestPicksSection: View {
    @ObservedObject var vm: LifestyleViewModel
    @EnvironmentObject var store: AppStore

    private var proteinLeft: Int {
        max(0, Int(180 - (vm.healthStats?.protein ?? 0)))
    }

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
        VStack(alignment: .leading, spacing: ForgeLayout.blockGap) {
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                ForgeCardHeader("AI Best Picks for Today")
                Text("\(proteinLeft)g protein left")
                    .font(HomeType.body)
                    .foregroundStyle(Color.textTertiary)
                    .forgeWrapping()
            }

            // Live ARIA coaching note over the protein-ranked picks (fallback: none).
            if let note = vm.aiBestPicksNote {
                ariaNote(note)
            }

            picksRail
        }
        .forgeContentCard(tint: .amber)
        .task { await vm.refreshBestPicksNote(store: store) }
    }

    private func ariaNote(_ note: String) -> some View {
        HStack(alignment: .top, spacing: FDS.Spacing.sm) {
            ARIAIdentityMark(state: .idle, mood: .energized, size: 14, amplitude: 0.22)
                .accessibilityHidden(true)
            Text(note)
                .font(HomeType.body)
                .foregroundStyle(Color.textSecondary)
                .forgeWrapping()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .forgeWell()
    }

    private var picksRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: ForgeLayout.rowGap) {
                ForEach(picks) { pick in
                    AIPickCard(pick: pick)
                }
            }
            .padding(.horizontal, ForgeLayout.cardPadding)
            .padding(.vertical, FDS.Spacing.sm)
        }
        .padding(.horizontal, -ForgeLayout.cardPadding)
    }
}

struct AIPickCard: View {
    let pick: AIRestaurantPick
    @ScaledMetric(relativeTo: .caption) private var cardWidthSize: CGFloat = 180

    var body: some View {
        VStack(alignment: .leading, spacing: ForgeLayout.rowGap) {
            HStack(spacing: FDS.Spacing.sm) {
                Text(pick.emoji)
                    .font(.system(size: 24))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ForgeLayout.labelValueGap) {
                    Text(pick.restaurant)
                        .font(HomeType.micro)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                    Text(pick.item)
                        .font(HomeType.status)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: ForgeLayout.pairGap) {
                Label("\(pick.cal) cal", systemImage: "flame.fill")
                    .font(HomeType.micro)
                    .foregroundStyle(FoodMacroPalette.calories)
                Label("\(pick.protein)g P", systemImage: "bolt.fill")
                    .font(HomeType.micro)
                    .foregroundStyle(FoodMacroPalette.protein)
            }
            Text(pick.reason)
                .font(HomeType.body)
                .foregroundStyle(Color.textTertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .forgeWell()
        .frame(width: ForgeLayout.scaledCap(cardWidthSize, base: 180), alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
