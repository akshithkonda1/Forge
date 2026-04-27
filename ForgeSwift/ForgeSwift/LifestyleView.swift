import SwiftUI

// MARK: - Restaurant Data Models

struct Restaurant: Identifiable {
    let id = UUID()
    let name: String
    let logo: String // SF Symbol or emoji
    let items: [MenuItem]
    let category: RestaurantCategory
}

struct MenuItem: Identifiable {
    let id = UUID()
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let serving: String
    let isHealthy: Bool
    
    var macroScore: Int {
        // Higher protein, lower calories = better score
        Int((Double(protein) / Double(calories) * 1000))
    }
}

enum RestaurantCategory: String, CaseIterable {
    case all = "All"
    case fastFood = "Fast Food"
    case chicken = "Chicken"
    case mexican = "Mexican"
    case burgers = "Burgers"
    case pizza = "Pizza"
    case healthy = "Healthy"
}

// MARK: - Lifestyle Tab (AI-Powered Life Optimization)

struct LifestyleView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedSegment = 0
    @State private var showAIInsights = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.background,
                    Color(hex: "0F1415"),
                    Color.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                LifestyleHeaderView(showAIInsights: $showAIInsights)
                    .padding(.top, 60)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                
                // Segment control
                LifestyleSegmentedControl(selectedIndex: $selectedSegment)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                
                // Content area
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        if selectedSegment == 0 {
                            AIOptimizationView()
                        } else if selectedSegment == 1 {
                            NutritionDatabaseView()
                        } else if selectedSegment == 2 {
                            DailyNutritionView()
                        } else {
                            WellbeingView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            
            // AI Insights Modal
            if showAIInsights {
                AIInsightsModal(isPresented: $showAIInsights)
            }
        }
    }
}

// MARK: - Header

struct LifestyleHeaderView: View {
    @Binding var showAIInsights: Bool
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Lifestyle")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Text("AI-Powered Optimization")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            // AI Insights button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showAIInsights = true
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.ember)
                    .frame(width: 44, height: 44)
                    .background(Color.ember.opacity(0.15))
                    .clipShape(Circle())
            }
        }
    }
}

// MARK: - Segmented Control

struct LifestyleSegmentedControl: View {
    @Binding var selectedIndex: Int
    let options = ["AI Optimize", "Restaurants", "Nutrition", "Wellbeing"]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<options.count, id: \.self) { index in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedIndex = index
                        }
                    } label: {
                        Text(options[index])
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(selectedIndex == index ? .textPrimary : .textTertiary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                selectedIndex == index
                                    ? Color.ember.opacity(0.15)
                                    : Color.surface.opacity(0.5)
                            )
                            .cornerRadius(20)
                    }
                }
            }
        }
    }
}

// MARK: - AI Optimization View

struct AIOptimizationView: View {
    @EnvironmentObject var store: AppStore
    
    var body: some View {
        VStack(spacing: 20) {
            // AI Life Analysis Card
            AILifeAnalysisCard()
            
            // Quality of Life Score
            QualityOfLifeCard()
            
            // AI Recommendations
            AIRecommendationsCard()
            
            // Mental Health Check
            MentalHealthCard()
            
            // Physical Wellbeing
            PhysicalWellbeingCard()
            
            // Optimization Goals
            OptimizationGoalsCard()
        }
    }
}

// MARK: - AI Life Analysis Card

struct AILifeAnalysisCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 24))
                    .foregroundColor(.ember)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Life Analysis")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    Text("Based on your behavior patterns")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                
                Spacer()
            }
            
            Divider()
                .background(Color.borderColor)
            
            VStack(alignment: .leading, spacing: 12) {
                AIInsightRow(
                    icon: "moon.zzz.fill",
                    label: "Sleep Pattern",
                    current: "7.2h avg",
                    optimal: "8h recommended",
                    status: .warning
                )
                
                AIInsightRow(
                    icon: "fork.knife",
                    label: "Nutrition Quality",
                    current: "78% whole foods",
                    optimal: "85%+ target",
                    status: .good
                )
                
                AIInsightRow(
                    icon: "figure.walk",
                    label: "Daily Movement",
                    current: "8,400 steps",
                    optimal: "10,000 steps",
                    status: .good
                )
                
                AIInsightRow(
                    icon: "brain.fill",
                    label: "Stress Level",
                    current: "Medium",
                    optimal: "Low target",
                    status: .warning
                )
            }
            
            Button {
                // View full analysis
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("View Full Analysis")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.ember)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct AIInsightRow: View {
    let icon: String
    let label: String
    let current: String
    let optimal: String
    let status: InsightStatus
    
    enum InsightStatus {
        case excellent, good, warning, poor
        
        var color: Color {
            switch self {
            case .excellent: return .success
            case .good: return .steel
            case .warning: return .warning
            case .poor: return .danger
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(status.color)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                HStack(spacing: 4) {
                    Text(current)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    
                    Text("→")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                    
                    Text(optimal)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }
            
            Spacer()
            
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Quality of Life Card

struct QualityOfLifeCard: View {
    let qolScore = 82 // Out of 100
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quality of Life Score")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            ZStack {
                Circle()
                    .stroke(Color.borderColor, lineWidth: 12)
                    .frame(width: 140, height: 140)
                
                Circle()
                    .trim(from: 0, to: CGFloat(qolScore) / 100)
                    .stroke(
                        LinearGradient(
                            colors: [.success, .ember],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(qolScore)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.textPrimary)
                    
                    Text("/ 100")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            
            VStack(alignment: .leading, spacing: 8) {
                QOLFactorRow(label: "Physical Health", value: 88, color: .success)
                QOLFactorRow(label: "Mental Wellbeing", value: 75, color: .steel)
                QOLFactorRow(label: "Energy Levels", value: 82, color: .ember)
                QOLFactorRow(label: "Sleep Quality", value: 79, color: .warning)
                QOLFactorRow(label: "Nutrition", value: 85, color: .success)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct QOLFactorRow: View {
    let label: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.borderColor.opacity(0.3))
                    .frame(width: 80, height: 6)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: CGFloat(value) * 0.8, height: 6)
            }
            
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - AI Recommendations Card

struct AIRecommendationsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.ember)
                
                Text("AI Recommendations")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            VStack(spacing: 12) {
                AIRecommendationItem(
                    title: "Increase protein intake by 30g",
                    description: "Your muscle recovery would improve with 180g daily protein. Currently at 150g.",
                    impact: "High",
                    category: "Nutrition"
                )
                
                AIRecommendationItem(
                    title: "Earlier bedtime (9:30 PM)",
                    description: "Your deep sleep increases by 18% when you sleep before 10 PM based on your Oura data.",
                    impact: "High",
                    category: "Sleep"
                )
                
                AIRecommendationItem(
                    title: "Add 10min morning sunlight",
                    description: "Cortisol regulation improves with early light exposure. Sets your circadian rhythm.",
                    impact: "Medium",
                    category: "Wellbeing"
                )
                
                AIRecommendationItem(
                    title: "Reduce caffeine after 2 PM",
                    description: "Late caffeine correlates with 40min less deep sleep in your tracking history.",
                    impact: "Medium",
                    category: "Sleep"
                )
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct AIRecommendationItem: View {
    let title: String
    let description: String
    let impact: String
    let category: String
    
    var impactColor: Color {
        impact == "High" ? .ember : impact == "Medium" ? .warning : .steel
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Text(impact)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(impactColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(impactColor.opacity(0.15))
                    .cornerRadius(6)
            }
            
            Text(description)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.textSecondary)
                .lineLimit(3)
            
            HStack {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9))
                Text(category)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.textTertiary)
        }
        .padding(12)
        .background(Color.surfaceElevated)
        .cornerRadius(10)
    }
}

// MARK: - Mental Health Card

struct MentalHealthCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.steel)
                
                Text("Mental Health Check-In")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            VStack(spacing: 12) {
                MentalHealthRow(label: "Mood Today", value: "Good", icon: "😊", color: .success)
                MentalHealthRow(label: "Stress Level", value: "Medium", icon: "😐", color: .warning)
                MentalHealthRow(label: "Energy", value: "High", icon: "⚡", color: .ember)
                MentalHealthRow(label: "Focus", value: "Excellent", icon: "🎯", color: .success)
            }
            
            Button {
                // Log mental state
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Log Daily Check-In")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.steel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.steel.opacity(0.1))
                .cornerRadius(10)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct MentalHealthRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(icon)
                .font(.system(size: 24))
            
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color.opacity(0.15))
                .cornerRadius(8)
        }
    }
}

// MARK: - Physical Wellbeing Card

struct PhysicalWellbeingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Physical Wellbeing")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            VStack(spacing: 12) {
                PhysicalMetricRow(
                    label: "Recovery Status",
                    value: "82%",
                    icon: "heart.fill",
                    color: .success,
                    trend: .up
                )
                
                PhysicalMetricRow(
                    label: "Hydration",
                    value: "Good",
                    icon: "drop.fill",
                    color: .steel,
                    trend: .neutral
                )
                
                PhysicalMetricRow(
                    label: "Muscle Soreness",
                    value: "Low",
                    icon: "figure.strengthtraining.traditional",
                    color: .success,
                    trend: .down
                )
                
                PhysicalMetricRow(
                    label: "Inflammation",
                    value: "Normal",
                    icon: "waveform.path.ecg",
                    color: .success,
                    trend: .neutral
                )
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct PhysicalMetricRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    let trend: Trend
    
    enum Trend {
        case up, down, neutral
        
        var symbol: String {
            switch self {
            case .up: return "arrow.up"
            case .down: return "arrow.down"
            case .neutral: return "minus"
            }
        }
        
        var color: Color {
            switch self {
            case .up: return .success
            case .down: return .danger
            case .neutral: return .textTertiary
            }
        }
    }
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 28)
            
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            HStack(spacing: 6) {
                Image(systemName: trend.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(trend.color)
                
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
        }
    }
}

// MARK: - Optimization Goals Card

struct OptimizationGoalsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optimization Goals")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            VStack(spacing: 12) {
                OptimizationGoalItem(
                    title: "Increase deep sleep to 90+ min",
                    progress: 0.75,
                    current: "82 min avg",
                    target: "90 min"
                )
                
                OptimizationGoalItem(
                    title: "Reduce stress markers",
                    progress: 0.6,
                    current: "Medium",
                    target: "Low"
                )
                
                OptimizationGoalItem(
                    title: "Hit 180g protein daily",
                    progress: 0.85,
                    current: "150g avg",
                    target: "180g"
                )
                
                OptimizationGoalItem(
                    title: "Morning routine consistency",
                    progress: 0.5,
                    current: "3/7 days",
                    target: "7/7 days"
                )
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct OptimizationGoalItem: View {
    let title: String
    let progress: Double
    let current: String
    let target: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
            
            HStack(spacing: 8) {
                Text(current)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
                
                Text(target)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ember)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderColor.opacity(0.3))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.ember, .emberLight],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(Color.surfaceElevated)
        .cornerRadius(10)
    }
}

// MARK: - Restaurant Nutrition Database

struct NutritionDatabaseView: View {
    @State private var selectedCategory: RestaurantCategory = .all
    @State private var searchText = ""
    @State private var selectedRestaurant: Restaurant?
    
    var body: some View {
        VStack(spacing: 20) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.textTertiary)
                
                TextField("Search restaurants or items", text: $searchText)
                    .foregroundColor(.textPrimary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(12)
            .background(Color.surface)
            .cornerRadius(12)
            
            // Category filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(RestaurantCategory.allCases, id: \.self) { category in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedCategory = category
                            }
                        } label: {
                            Text(category.rawValue)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(selectedCategory == category ? .textPrimary : .textTertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    selectedCategory == category
                                        ? Color.ember.opacity(0.15)
                                        : Color.surface.opacity(0.5)
                                )
                                .cornerRadius(16)
                        }
                    }
                }
            }
            
            // AI Best Picks for today's goals
            AIBestPicksSection()

            // Restaurant grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(filteredRestaurants) { restaurant in
                    Button {
                        selectedRestaurant = restaurant
                    } label: {
                        RestaurantCard(restaurant: restaurant)
                    }
                }
            }
        }
        .sheet(item: $selectedRestaurant) { restaurant in
            RestaurantMenuSheet(restaurant: restaurant, isPresented: Binding(
                get: { selectedRestaurant != nil },
                set: { if !$0 { selectedRestaurant = nil } }
            ))
        }
    }
    
    var filteredRestaurants: [Restaurant] {
        let filtered = selectedCategory == .all 
            ? popularRestaurants 
            : popularRestaurants.filter { $0.category == selectedCategory }
        
        if searchText.isEmpty {
            return filtered
        } else {
            return filtered.filter { 
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.items.contains { $0.name.localizedCaseInsensitiveContains(searchText) }
            }
        }
    }
}

struct RestaurantCard: View {
    let restaurant: Restaurant
    
    var body: some View {
        VStack(spacing: 12) {
            Text(restaurant.logo)
                .font(.system(size: 48))
            
            Text(restaurant.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.textPrimary)
            
            Text("\(restaurant.items.count) items")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.surface)
        .cornerRadius(12)
    }
}

// MARK: - Restaurant Menu Sheet

struct RestaurantMenuSheet: View {
    let restaurant: Restaurant
    @Binding var isPresented: Bool
    @State private var sortBy: MenuSort = .calories
    
    enum MenuSort: String, CaseIterable {
        case calories = "Calories"
        case protein = "Protein"
        case name = "Name"
        case healthy = "Healthiest"
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text(restaurant.logo)
                            .font(.system(size: 40))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(restaurant.name)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.textPrimary)
                            
                            Text("\(restaurant.items.count) menu items")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.textSecondary)
                        }
                        
                        Spacer()
                    }
                    .padding(20)
                    .background(Color.surface)
                    
                    // Sort picker
                    Picker("Sort by", selection: $sortBy) {
                        ForEach(MenuSort.allCases, id: \.self) { sort in
                            Text(sort.rawValue).tag(sort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    
                    // Menu items
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(sortedItems) { item in
                                MenuItemCard(item: item)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(.ember)
                }
            }
        }
    }
    
    var sortedItems: [MenuItem] {
        switch sortBy {
        case .calories:
            return restaurant.items.sorted { $0.calories < $1.calories }
        case .protein:
            return restaurant.items.sorted { $0.protein > $1.protein }
        case .name:
            return restaurant.items.sorted { $0.name < $1.name }
        case .healthy:
            return restaurant.items.sorted { $0.macroScore > $1.macroScore }
        }
    }
}

struct MenuItemCard: View {
    let item: MenuItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    
                    Text(item.serving)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
                
                Spacer()
                
                if item.isHealthy {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.success)
                }
            }
            
            Divider()
                .background(Color.borderColor)
            
            HStack(spacing: 20) {
                MacroChip(label: "Cal", value: "\(item.calories)", color: .ember)
                MacroChip(label: "P", value: "\(item.protein)g", color: .steel)
                MacroChip(label: "C", value: "\(item.carbs)g", color: Color(hex: "FFB84D"))
                MacroChip(label: "F", value: "\(item.fat)g", color: Color(hex: "A855F7"))
            }
        }
        .padding(16)
        .background(Color.surface)
        .cornerRadius(12)
    }
}

struct MacroChip: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
            
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - AI Nutrition Coach Card

struct AINutritionCoachCard: View {
    @State private var isAnalyzing = true
    @State private var currentTipIndex = 0
    @State private var sparkleOpacity: Double = 1.0

    private let tips: [(icon: String, color: Color, headline: String, body: String)] = [
        (
            icon: "bolt.fill",
            color: .ember,
            headline: "Protein gap — act before dinner",
            body: "You're 35g short on protein with one meal left. Add a chicken breast or Greek yogurt to hit your 180g goal."
        ),
        (
            icon: "drop.fill",
            color: .steel,
            headline: "Hydration is on track",
            body: "You've hit 6 of 8 glasses today. Keep it up — good hydration improves protein synthesis by up to 12%."
        ),
        (
            icon: "moon.stars.fill",
            color: Color(hex: "A855F7"),
            headline: "Carbs timed well for recovery",
            body: "Your post-workout carb intake was within the 30-min window. Glycogen replenishment is optimal tonight."
        ),
    ]

    var currentTip: (icon: String, color: Color, headline: String, body: String) {
        tips[currentTipIndex % tips.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.ember.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.ember)
                        .opacity(sparkleOpacity)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Nutrition Coach")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(isAnalyzing ? "Analyzing today's intake…" : "Insight ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textTertiary)
                }

                Spacer()

                // Refresh tip button
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        currentTipIndex += 1
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(Color.surfaceElevated)
                        .clipShape(Circle())
                }
            }

            if !isAnalyzing {
                Divider().background(Color.borderColor)

                // Tip content
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: currentTip.icon)
                        .font(.system(size: 20))
                        .foregroundColor(currentTip.color)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentTip.headline)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)

                        Text(currentTip.body)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))

                // Macro snapshot
                HStack(spacing: 0) {
                    AIMacroSnapshotChip(label: "Protein", filled: 145, total: 180, color: .ember)
                    Divider().frame(height: 24).background(Color.borderColor)
                    AIMacroSnapshotChip(label: "Carbs", filled: 220, total: 280, color: .steel)
                    Divider().frame(height: 24).background(Color.borderColor)
                    AIMacroSnapshotChip(label: "Fats", filled: 58, total: 70, color: Color(hex: "FFB84D"))
                    Divider().frame(height: 24).background(Color.borderColor)
                    AIMacroSnapshotChip(label: "Cal", filled: 2140, total: 2600, color: Color(hex: "A855F7"))
                }
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.ember.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            // Pulse the sparkle icon while analyzing
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                sparkleOpacity = 0.3
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeOut(duration: 0.4)) {
                    isAnalyzing = false
                    sparkleOpacity = 1.0
                }
            }
        }
    }
}

struct AIMacroSnapshotChip: View {
    let label: String
    let filled: Int
    let total: Int
    let color: Color

    var pct: Int { Int(Double(filled) / Double(total) * 100) }

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.textTertiary)
            Text("\(pct)%")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
    }
}

// MARK: - AI Meal Suggestions Card

struct AIMealSuggestionsCard: View {
    @State private var suggestionSet = 0

    private let suggestionSets: [[AIMealSuggestion]] = [
        [
            AIMealSuggestion(name: "Grilled Chicken + Rice", cal: 480, protein: 42, carbs: 52, fat: 8, reason: "Fills your 35g protein gap perfectly"),
            AIMealSuggestion(name: "Greek Yogurt Parfait", cal: 320, protein: 28, carbs: 38, fat: 6, reason: "Light option, hits protein without blowing calories"),
            AIMealSuggestion(name: "Tuna Avocado Bowl", cal: 410, protein: 38, carbs: 24, fat: 18, reason: "High protein + healthy fats for recovery"),
        ],
        [
            AIMealSuggestion(name: "Egg White Omelette", cal: 290, protein: 32, carbs: 10, fat: 9, reason: "Clean protein, minimal calories left for the day"),
            AIMealSuggestion(name: "Salmon + Sweet Potato", cal: 520, protein: 36, carbs: 48, fat: 14, reason: "Omega-3s boost recovery alongside protein"),
            AIMealSuggestion(name: "Cottage Cheese & Fruit", cal: 240, protein: 26, carbs: 28, fat: 4, reason: "Casein protein — ideal before bed"),
        ],
        [
            AIMealSuggestion(name: "Turkey Lettuce Wraps", cal: 360, protein: 34, carbs: 18, fat: 12, reason: "Low carb, high protein to finish the day"),
            AIMealSuggestion(name: "Protein Smoothie Bowl", cal: 420, protein: 38, carbs: 44, fat: 8, reason: "Quick macro boost with micronutrients"),
            AIMealSuggestion(name: "Shrimp Stir-Fry", cal: 390, protein: 36, carbs: 32, fat: 10, reason: "Lean protein + veggie micronutrients"),
        ],
    ]

    var suggestions: [AIMealSuggestion] {
        suggestionSets[suggestionSet % suggestionSets.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.steel)
                    Text("AI Meal Suggestions")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        suggestionSet += 1
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Regenerate")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.steel)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.steel.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            Text("Based on 460 cal · 35g protein remaining")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textTertiary)

            VStack(spacing: 10) {
                ForEach(suggestions) { suggestion in
                    AIMealSuggestionRow(suggestion: suggestion)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                        .id("\(suggestionSet)-\(suggestion.id)")
                }
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
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

struct AIMealSuggestionRow: View {
    let suggestion: AIMealSuggestion
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(suggestion.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                        Text(suggestion.reason)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(suggestion.cal) cal")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.ember)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                .padding(12)
            }

            if isExpanded {
                HStack(spacing: 0) {
                    MacroChip(label: "P", value: "\(suggestion.protein)g", color: .steel)
                    MacroChip(label: "C", value: "\(suggestion.carbs)g", color: Color(hex: "FFB84D"))
                    MacroChip(label: "F", value: "\(suggestion.fat)g", color: Color(hex: "A855F7"))
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.surfaceElevated)
        .cornerRadius(10)
    }
}

// MARK: - AI Best Picks Section (Restaurants)

struct AIBestPicksSection: View {
    private let picks: [AIRestaurantPick] = [
        AIRestaurantPick(restaurant: "Chipotle", emoji: "🌯", item: "Chicken Bowl (no rice)", cal: 450, protein: 43, reason: "Best protein-to-calorie ratio today"),
        AIRestaurantPick(restaurant: "Chick-fil-A", emoji: "🐔", item: "Grilled Nuggets 12pc", cal: 200, protein: 38, reason: "Leanest option, fits your 460 cal budget"),
        AIRestaurantPick(restaurant: "Subway", emoji: "🥖", item: "Rotisserie Chicken 6\"", cal: 350, protein: 30, reason: "Hits protein gap with room for sides"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ember)
                Text("AI Best Picks for Today")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("35g protein left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(picks) { pick in
                        AIRestaurantPickCard(pick: pick)
                    }
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.ember.opacity(0.08), Color.surface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.ember.opacity(0.18), lineWidth: 1)
        )
    }
}

struct AIRestaurantPick: Identifiable {
    let id = UUID()
    let restaurant: String
    let emoji: String
    let item: String
    let cal: Int
    let protein: Int
    let reason: String
}

struct AIRestaurantPickCard: View {
    let pick: AIRestaurantPick

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(pick.emoji)
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.restaurant)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.textTertiary)
                    Text(pick.item)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Label("\(pick.cal) cal", systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                Label("\(pick.protein)g P", systemImage: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.steel)
            }

            Text(pick.reason)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 180)
        .padding(14)
        .background(Color.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.ember.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Daily Nutrition View

struct DailyNutritionView: View {
    var body: some View {
        VStack(spacing: 20) {
            // AI Nutrition Coach — personalized daily insight
            AINutritionCoachCard()

            // Daily Macros Card
            VStack(alignment: .leading, spacing: 16) {
                Text("Today's Macros")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)

                MacroProgressBar(label: "Protein", current: 145, target: 180, color: .ember)
                MacroProgressBar(label: "Carbs", current: 220, target: 280, color: .steel)
                MacroProgressBar(label: "Fats", current: 58, target: 70, color: Color(hex: "FFB84D"))

                HStack {
                    Text("2,140 / 2,600 cal")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    Text("460 left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.ember)
                }
            }
            .padding(20)
            .background(Color.surface)
            .cornerRadius(16)

            // Meal Log Card
            VStack(alignment: .leading, spacing: 12) {
                Text("Meal Log")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)

                MealLogItem(meal: "Breakfast", time: "7:30 AM", calories: 520)
                MealLogItem(meal: "Lunch", time: "12:45 PM", calories: 680)
                MealLogItem(meal: "Snack", time: "3:15 PM", calories: 240)
                MealLogItem(meal: "Dinner", time: "6:30 PM", calories: 700)

                Button {
                    // Add meal action
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Log Meal")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.ember)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.ember.opacity(0.1))
                    .cornerRadius(10)
                }
            }
            .padding(20)
            .background(Color.surface)
            .cornerRadius(16)

            // AI Meal Suggestions — fills remaining macros
            AIMealSuggestionsCard()

            // Water Intake
            WaterIntakeCard()

            // Micronutrients (new)
            MicronutrientsCard()
        }
    }
}

struct MicronutrientsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Micronutrients")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            VStack(spacing: 12) {
                MicroProgressRow(label: "Vitamin D", current: 800, target: 1000, unit: "IU", color: .warning)
                MicroProgressRow(label: "Omega-3", current: 1.2, target: 2.0, unit: "g", color: .steel)
                MicroProgressRow(label: "Magnesium", current: 320, target: 400, unit: "mg", color: .success)
                MicroProgressRow(label: "Iron", current: 14, target: 18, unit: "mg", color: .ember)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct MicroProgressRow: View {
    let label: String
    let current: Double
    let target: Double
    let unit: String
    let color: Color
    
    var progress: CGFloat {
        CGFloat(current / target)
    }
    
    var formattedValue: String {
        // Use decimal format if value is less than 10, otherwise use integer
        if current < 10 {
            return String(format: "%.1f / %.1f %@", current, target, unit)
        } else {
            return "\(Int(current)) / \(Int(target)) \(unit)"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderColor.opacity(0.3))
                    
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Wellbeing View

struct WellbeingView: View {
    var body: some View {
        VStack(spacing: 20) {
            // Daily Habits
            DailyHabitsCard()
            
            // Mindfulness
            MindfulnessCard()
            
            // Stress Management
            StressManagementCard()
            
            // Sleep Optimization
            SleepOptimizationCard()
        }
    }
}

struct DailyHabitsCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Daily Habits")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HabitCheckItem(habit: "Morning sunlight (10 min)", isComplete: true)
            HabitCheckItem(habit: "Meditation (5 min)", isComplete: true)
            HabitCheckItem(habit: "Read (20 min)", isComplete: false)
            HabitCheckItem(habit: "Mobility work (10 min)", isComplete: true)
            HabitCheckItem(habit: "Cold shower", isComplete: false)
            HabitCheckItem(habit: "Journaling", isComplete: false)
            
            Divider()
                .background(Color.borderColor)
                .padding(.vertical, 8)
            
            HStack {
                Text("Streak")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(.ember)
                    Text("7 days")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(16)
            .background(Color.surfaceElevated)
            .cornerRadius(12)
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct MindfulnessCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mindfulness")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("5 min")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text("Today")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("42 min")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.ember)
                    Text("This week")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
            }
            
            Button {
                // Start meditation
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start Meditation")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.ember)
                .cornerRadius(12)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct StressManagementCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stress Management")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            HStack(spacing: 12) {
                VStack(spacing: 8) {
                    Text("😌")
                        .font(.system(size: 32))
                    Text("Low")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.success.opacity(0.1))
                .cornerRadius(10)
                
                VStack(spacing: 8) {
                    Text("😐")
                        .font(.system(size: 32))
                    Text("Medium")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.ember.opacity(0.15))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.ember, lineWidth: 2)
                )
                
                VStack(spacing: 8) {
                    Text("😰")
                        .font(.system(size: 32))
                    Text("High")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.danger.opacity(0.1))
                .cornerRadius(10)
            }
            
            Text("Current stress: Medium")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Text("Try: 5-minute breathing exercise or a short walk")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.textTertiary)
                .italic()
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct SleepOptimizationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sleep Optimization Tips")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            VStack(spacing: 10) {
                SleepTipRow(icon: "moon.fill", tip: "Aim for bed by 10 PM tonight", color: .steel)
                SleepTipRow(icon: "iphone.slash", tip: "No screens 45 min before bed", color: .warning)
                SleepTipRow(icon: "thermometer.medium", tip: "Keep room at 65-68°F", color: .success)
                SleepTipRow(icon: "cup.and.saucer.fill", tip: "No caffeine after 2 PM", color: .danger)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(16)
    }
}

struct SleepTipRow: View {
    let icon: String
    let tip: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(tip)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Spacer()
        }
        .padding(12)
        .background(Color.surfaceElevated)
        .cornerRadius(8)
    }
}

struct MacroProgressBar: View {
    let label: String
    let current: Int
    let target: Int
    let color: Color
    
    var progress: CGFloat {
        CGFloat(current) / CGFloat(target)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                Text("\(current)g / \(target)g")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.borderColor.opacity(0.3))
                    
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color)
                        .frame(width: geo.size.width * min(progress, 1.0))
                }
            }
            .frame(height: 8)
        }
    }
}

struct MealLogItem: View {
    let meal: String
    let time: String
    let calories: Int
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(time)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            Text("\(calories) cal")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct WaterIntakeCard: View {
    @State private var glassesConsumed = 6
    let target = 8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Water Intake")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            
            HStack(spacing: 8) {
                ForEach(0..<target, id: \.self) { index in
                    Image(systemName: index < glassesConsumed ? "drop.fill" : "drop")
                        .foregroundColor(index < glassesConsumed ? Color(hex: "4A9EFF") : .textTertiary.opacity(0.3))
                        .font(.system(size: 24))
                }
            }
            
            HStack {
                Text("\(glassesConsumed) / \(target) glasses")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                Spacer()
                Button {
                    if glassesConsumed < target {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            glassesConsumed += 1
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.ember)
                        .font(.system(size: 20))
                }
            }
        }
        .padding(20)
        .background(Color.cardBackground)
        .cornerRadius(16)
    }
}

struct HabitCheckItem: View {
    let habit: String
    @State var isComplete: Bool
    
    var body: some View {
        HStack {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isComplete.toggle()
                }
            } label: {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isComplete ? .ember : .textTertiary)
                    .font(.system(size: 24))
            }
            
            Text(habit)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isComplete ? .textSecondary : .textPrimary)
                .strikethrough(isComplete, color: .textSecondary)
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct WellnessMetricRow: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 20))
                .frame(width: 32)
            
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            
            Spacer()
            
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .padding(.vertical, 4)
    }
}

struct PlaceholderCard: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(.ember.opacity(0.6))
            
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.textPrimary)
            
            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color.cardBackground.opacity(0.5))
        .cornerRadius(16)
    }
}

// MARK: - AI Insights Modal

struct AIInsightsModal: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var store: AppStore
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 20) {
                    // Handle
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.textTertiary)
                        .frame(width: 40, height: 5)
                        .padding(.top, 12)
                    
                    // Header
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24))
                            .foregroundColor(.ember)
                        
                        Text("AI Life Insights")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 16) {
                            AIInsightCard(
                                title: "Your Lifestyle Pattern",
                                insight: "Based on 30 days of tracking, you're most productive between 9 AM - 12 PM. Your workouts perform best when scheduled in this window. Energy dips at 3 PM correlate with lunch timing and composition.",
                                action: "Optimize schedule",
                                color: .ember
                            )
                            
                            AIInsightCard(
                                title: "Nutrition Optimization",
                                insight: "You hit protein targets 6/7 days but carb intake is inconsistent (180-320g range). Stabilizing carbs at 250g would improve training performance and recovery consistency.",
                                action: "Adjust macros",
                                color: .steel
                            )
                            
                            AIInsightCard(
                                title: "Sleep Quality Prediction",
                                insight: "When you train after 7 PM, deep sleep decreases by 22 minutes on average. Morning or midday sessions result in better recovery metrics.",
                                action: "Reschedule workouts",
                                color: Color(hex: "A855F7")
                            )
                            
                            AIInsightCard(
                                title: "Stress Triggers",
                                insight: "HRV drops on Mondays and Thursdays. This pattern suggests work-related stress on these days. Consider light mobility work instead of heavy lifting.",
                                action: "Adjust weekly plan",
                                color: .warning
                            )
                            
                            AIInsightCard(
                                title: "Recovery Optimization",
                                insight: "Your body responds best to a 48-hour recovery window for major muscle groups. Current 72-hour splits might be leaving gains on the table.",
                                action: "Update split",
                                color: .success
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
                .frame(maxHeight: UIScreen.main.bounds.height * 0.75)
                .background(Color.surface)
                .cornerRadius(24, corners: [.topLeft, .topRight])
            }
        }
        .transition(.move(edge: .bottom))
    }
}

struct AIInsightCard: View {
    let title: String
    let insight: String
    let action: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Spacer()
                
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            
            Text(insight)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)
            
            Button {
                // Take action
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14))
                    Text(action)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(color)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

// MARK: - Supporting Views

// MARK: - Restaurant Data

let popularRestaurants: [Restaurant] = [
    // Raising Cane's
    Restaurant(
        name: "Raising Cane's",
        logo: "🍗",
        items: [
            MenuItem(name: "Box Combo (4 tenders)", calories: 1220, protein: 56, carbs: 120, fat: 55, serving: "1 combo", isHealthy: false),
            MenuItem(name: "3 Finger Combo", calories: 1030, protein: 46, carbs: 104, fat: 46, serving: "1 combo", isHealthy: false),
            MenuItem(name: "Caniac Combo (6 tenders)", calories: 1760, protein: 82, carbs: 152, fat: 82, serving: "1 combo", isHealthy: false),
            MenuItem(name: "Chicken Finger (1 piece)", calories: 130, protein: 10, carbs: 8, fat: 6, serving: "1 tender", isHealthy: true),
            MenuItem(name: "Cane's Sauce", calories: 190, protein: 0, carbs: 6, fat: 19, serving: "1 container", isHealthy: false),
            MenuItem(name: "Crinkle Fries", calories: 390, protein: 5, carbs: 50, fat: 18, serving: "1 order", isHealthy: false),
            MenuItem(name: "Texas Toast", calories: 150, protein: 4, carbs: 18, fat: 7, serving: "1 slice", isHealthy: false),
            MenuItem(name: "Coleslaw", calories: 170, protein: 2, carbs: 14, fat: 13, serving: "1 order", isHealthy: false),
        ],
        category: .chicken
    ),
    
    // McDonald's
    Restaurant(
        name: "McDonald's",
        logo: "🍔",
        items: [
            MenuItem(name: "Big Mac", calories: 550, protein: 25, carbs: 45, fat: 30, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Quarter Pounder with Cheese", calories: 520, protein: 30, carbs: 41, fat: 26, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "McDouble", calories: 400, protein: 22, carbs: 33, fat: 20, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "10 Piece Chicken McNuggets", calories: 420, protein: 24, carbs: 25, fat: 24, serving: "10 pieces", isHealthy: false),
            MenuItem(name: "Egg McMuffin", calories: 310, protein: 17, carbs: 30, fat: 13, serving: "1 sandwich", isHealthy: true),
            MenuItem(name: "Sausage Egg McMuffin", calories: 480, protein: 21, carbs: 30, fat: 30, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Medium Fries", calories: 320, protein: 4, carbs: 43, fat: 15, serving: "1 order", isHealthy: false),
            MenuItem(name: "Large Fries", calories: 480, protein: 6, carbs: 64, fat: 23, serving: "1 order", isHealthy: false),
            MenuItem(name: "Grilled Chicken Sandwich", calories: 380, protein: 37, carbs: 44, fat: 7, serving: "1 sandwich", isHealthy: true),
            MenuItem(name: "Southwest Grilled Chicken Salad", calories: 350, protein: 37, carbs: 27, fat: 12, serving: "1 salad", isHealthy: true),
        ],
        category: .burgers
    ),
    
    // Taco Bell
    Restaurant(
        name: "Taco Bell",
        logo: "🌮",
        items: [
            MenuItem(name: "Crunchy Taco", calories: 170, protein: 8, carbs: 13, fat: 10, serving: "1 taco", isHealthy: false),
            MenuItem(name: "Soft Taco", calories: 180, protein: 9, carbs: 18, fat: 9, serving: "1 taco", isHealthy: false),
            MenuItem(name: "Burrito Supreme", calories: 380, protein: 14, carbs: 50, fat: 14, serving: "1 burrito", isHealthy: false),
            MenuItem(name: "Chicken Power Bowl", calories: 470, protein: 26, carbs: 50, fat: 19, serving: "1 bowl", isHealthy: true),
            MenuItem(name: "Crunchwrap Supreme", calories: 530, protein: 16, carbs: 71, fat: 21, serving: "1 item", isHealthy: false),
            MenuItem(name: "Quesadilla (Chicken)", calories: 510, protein: 27, carbs: 37, fat: 28, serving: "1 quesadilla", isHealthy: false),
            MenuItem(name: "Nachos BellGrande", calories: 740, protein: 19, carbs: 77, fat: 39, serving: "1 order", isHealthy: false),
            MenuItem(name: "Black Beans", calories: 80, protein: 5, carbs: 14, fat: 0, serving: "1 side", isHealthy: true),
            MenuItem(name: "Fresco Crunchy Taco", calories: 140, protein: 7, carbs: 13, fat: 7, serving: "1 taco", isHealthy: true),
        ],
        category: .mexican
    ),
    
    // Chick-fil-A
    Restaurant(
        name: "Chick-fil-A",
        logo: "🐔",
        items: [
            MenuItem(name: "Chicken Sandwich", calories: 440, protein: 28, carbs: 41, fat: 19, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Spicy Chicken Sandwich", calories: 450, protein: 28, carbs: 43, fat: 19, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Grilled Chicken Sandwich", calories: 320, protein: 30, carbs: 42, fat: 6, serving: "1 sandwich", isHealthy: true),
            MenuItem(name: "8-count Nuggets", calories: 250, protein: 27, carbs: 11, fat: 11, serving: "8 pieces", isHealthy: true),
            MenuItem(name: "12-count Nuggets", calories: 380, protein: 40, carbs: 16, fat: 17, serving: "12 pieces", isHealthy: true),
            MenuItem(name: "Grilled Nuggets (8-count)", calories: 130, protein: 25, carbs: 1, fat: 3, serving: "8 pieces", isHealthy: true),
            MenuItem(name: "Waffle Potato Fries (Medium)", calories: 360, protein: 4, carbs: 43, fat: 19, serving: "1 order", isHealthy: false),
            MenuItem(name: "Cobb Salad (Grilled)", calories: 390, protein: 40, carbs: 28, fat: 14, serving: "1 salad", isHealthy: true),
            MenuItem(name: "Market Salad (Grilled)", calories: 330, protein: 28, carbs: 31, fat: 12, serving: "1 salad", isHealthy: true),
        ],
        category: .chicken
    ),
    
    // Chipotle
    Restaurant(
        name: "Chipotle",
        logo: "🌯",
        items: [
            MenuItem(name: "Chicken Bowl (no rice)", calories: 320, protein: 42, carbs: 21, fat: 8, serving: "1 bowl", isHealthy: true),
            MenuItem(name: "Steak Bowl (with rice)", calories: 630, protein: 34, carbs: 67, fat: 24, serving: "1 bowl", isHealthy: false),
            MenuItem(name: "Chicken Burrito", calories: 1025, protein: 65, carbs: 123, fat: 30, serving: "1 burrito", isHealthy: false),
            MenuItem(name: "Carnitas Bowl", calories: 590, protein: 32, carbs: 63, fat: 22, serving: "1 bowl", isHealthy: false),
            MenuItem(name: "Veggie Bowl", calories: 430, protein: 16, carbs: 68, fat: 12, serving: "1 bowl", isHealthy: true),
            MenuItem(name: "Chicken Salad", calories: 500, protein: 44, carbs: 36, fat: 21, serving: "1 salad", isHealthy: true),
            MenuItem(name: "Guacamole", calories: 230, protein: 2, carbs: 8, fat: 22, serving: "1 side", isHealthy: true),
            MenuItem(name: "Brown Rice", calories: 210, protein: 4, carbs: 36, fat: 6, serving: "1 side", isHealthy: true),
        ],
        category: .mexican
    ),
    
    // Subway
    Restaurant(
        name: "Subway",
        logo: "🥖",
        items: [
            MenuItem(name: "6\" Turkey Breast", calories: 280, protein: 18, carbs: 46, fat: 4, serving: "6 inch sub", isHealthy: true),
            MenuItem(name: "6\" Chicken & Bacon Ranch", calories: 570, protein: 36, carbs: 47, fat: 28, serving: "6 inch sub", isHealthy: false),
            MenuItem(name: "6\" Veggie Delite", calories: 230, protein: 9, carbs: 44, fat: 3, serving: "6 inch sub", isHealthy: true),
            MenuItem(name: "6\" Spicy Italian", calories: 480, protein: 21, carbs: 46, fat: 24, serving: "6 inch sub", isHealthy: false),
            MenuItem(name: "Grilled Chicken Salad", calories: 130, protein: 19, carbs: 10, fat: 3, serving: "1 salad", isHealthy: true),
            MenuItem(name: "12\" Turkey Breast", calories: 560, protein: 36, carbs: 92, fat: 7, serving: "footlong", isHealthy: true),
        ],
        category: .healthy
    ),
    
    // Wendy's
    Restaurant(
        name: "Wendy's",
        logo: "🍔",
        items: [
            MenuItem(name: "Dave's Single", calories: 590, protein: 30, carbs: 39, fat: 34, serving: "1 burger", isHealthy: false),
            MenuItem(name: "Spicy Chicken Sandwich", calories: 510, protein: 28, carbs: 50, fat: 21, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Grilled Chicken Sandwich", calories: 350, protein: 35, carbs: 37, fat: 8, serving: "1 sandwich", isHealthy: true),
            MenuItem(name: "10 Piece Chicken Nuggets", calories: 450, protein: 23, carbs: 31, fat: 27, serving: "10 pieces", isHealthy: false),
            MenuItem(name: "Apple Pecan Chicken Salad", calories: 560, protein: 34, carbs: 40, fat: 30, serving: "1 salad", isHealthy: true),
            MenuItem(name: "Southwest Avocado Salad (Grilled)", calories: 540, protein: 43, carbs: 32, fat: 27, serving: "1 salad", isHealthy: true),
        ],
        category: .burgers
    ),
    
    // Panera Bread
    Restaurant(
        name: "Panera Bread",
        logo: "🥗",
        items: [
            MenuItem(name: "Mediterranean Grain Bowl", calories: 430, protein: 16, carbs: 48, fat: 21, serving: "1 bowl", isHealthy: true),
            MenuItem(name: "Chicken Noodle Soup (Cup)", calories: 90, protein: 7, carbs: 10, fat: 3, serving: "1 cup", isHealthy: true),
            MenuItem(name: "Green Goddess Cobb Salad", calories: 550, protein: 42, carbs: 23, fat: 33, serving: "1 salad", isHealthy: true),
            MenuItem(name: "Turkey Bravo Sandwich", calories: 830, protein: 44, carbs: 76, fat: 37, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Greek Salad", calories: 400, protein: 14, carbs: 19, fat: 31, serving: "1 salad", isHealthy: true),
        ],
        category: .healthy
    ),
]

// MARK: - Previews

#Preview {
    LifestyleView()
        .environmentObject(AppStore())
}
