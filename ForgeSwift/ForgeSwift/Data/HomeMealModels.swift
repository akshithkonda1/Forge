import Foundation

enum MealCuisine: String, CaseIterable, Identifiable, Codable, Hashable {
    case american, mexican, italian, mediterranean, indian, thai, japanese
    case korean, chinese, middleEastern, greek, vietnamese, caribbean, french, spanish

    var id: String { rawValue }

    var label: String {
        switch self {
        case .american: return "American"
        case .mexican: return "Mexican"
        case .italian: return "Italian"
        case .mediterranean: return "Mediterranean"
        case .indian: return "Indian"
        case .thai: return "Thai"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chinese: return "Chinese"
        case .middleEastern: return "Middle Eastern"
        case .greek: return "Greek"
        case .vietnamese: return "Vietnamese"
        case .caribbean: return "Caribbean"
        case .french: return "French"
        case .spanish: return "Spanish"
        }
    }

    var emoji: String {
        switch self {
        case .american: return "🇺🇸"
        case .mexican: return "🌮"
        case .italian: return "🍝"
        case .mediterranean: return "🫒"
        case .indian: return "🍛"
        case .thai: return "🌶️"
        case .japanese: return "🍱"
        case .korean: return "🍲"
        case .chinese: return "🥢"
        case .middleEastern: return "🥙"
        case .greek: return "🥗"
        case .vietnamese: return "🍜"
        case .caribbean: return "🏝️"
        case .french: return "🥖"
        case .spanish: return "🥘"
        }
    }
}

enum MealCourse: String, CaseIterable, Identifiable, Codable, Hashable {
    case breakfast, lunch, dinner

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        }
    }
}

/// How the dish is cooked. Drives both the generated method steps and the active time.
enum CookMethod: String, CaseIterable, Identifiable, Codable, Hashable {
    case sheetPan, stirFry, curry, skillet, grill, braise, soup, salad
    case bowl, taco, pasta, chili, airFryer, slowCooker, noodleBowl
    case hash, frittata, porridge, bake, wrap, congee, poke, skewers

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sheetPan: return "Sheet-Pan"
        case .stirFry: return "Stir-Fry"
        case .curry: return "Curry"
        case .skillet: return "Skillet"
        case .grill: return "Grilled"
        case .braise: return "Braise"
        case .soup: return "Soup"
        case .salad: return "Salad"
        case .bowl: return "Bowl"
        case .taco: return "Tacos"
        case .pasta: return "Pasta"
        case .chili: return "Chili"
        case .airFryer: return "Air-Fryer"
        case .slowCooker: return "Slow-Cooker"
        case .noodleBowl: return "Noodle Bowl"
        case .hash: return "Hash"
        case .frittata: return "Frittata"
        case .porridge: return "Porridge Bowl"
        case .bake: return "Bake"
        case .wrap: return "Wrap"
        case .congee: return "Congee"
        case .poke: return "Poke Bowl"
        case .skewers: return "Skewers"
        }
    }

    var icon: String {
        switch self {
        case .sheetPan, .bake, .airFryer: return "oven.fill"
        case .stirFry, .skillet, .hash, .frittata: return "frying.pan.fill"
        case .curry, .soup, .chili, .braise, .slowCooker, .congee: return "cooktop.fill"
        case .salad, .poke, .bowl, .wrap, .taco: return "leaf.fill"
        case .pasta, .noodleBowl: return "fork.knife"
        case .grill, .skewers: return "flame.fill"
        case .porridge: return "cup.and.saucer.fill"
        }
    }

    /// Meals in these formats reheat and portion well.
    var isMealPrepFriendly: Bool {
        switch self {
        case .sheetPan, .curry, .soup, .chili, .braise, .slowCooker, .bake, .bowl, .congee:
            return true
        default:
            return false
        }
    }
}

enum MealDietTag: String, CaseIterable, Identifiable, Codable, Hashable {
    case highProtein, vegetarian, vegan, glutenFree, dairyFree, nutFree, lowCarb, quick, mealPrep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .highProtein: return "High protein"
        case .vegetarian: return "Vegetarian"
        case .vegan: return "Vegan"
        case .glutenFree: return "Gluten-free"
        case .dairyFree: return "Dairy-free"
        case .nutFree: return "Nut-free"
        case .lowCarb: return "Low carb"
        case .quick: return "Under 30 min"
        case .mealPrep: return "Meal-prep"
        }
    }

    var icon: String {
        switch self {
        case .highProtein: return "bolt.fill"
        case .vegetarian: return "leaf.fill"
        case .vegan: return "carrot.fill"
        case .glutenFree: return "circle.slash"
        case .dairyFree: return "drop.triangle"
        case .nutFree: return "exclamationmark.shield"
        case .lowCarb: return "chart.line.downtrend.xyaxis"
        case .quick: return "timer"
        case .mealPrep: return "shippingbox.fill"
        }
    }
}

struct MealComponent: Hashable, Identifiable {
    let item: PantryItem
    let grams: Double

    var id: String { item.key }
    var macros: FoodMacros { item.per100.forGrams(grams) }

    /// "170 g chicken breast (6 oz)" — grams for accuracy, ounces or a human measure for
    /// the person actually standing at the counter.
    var displayLine: String {
        if let measure = item.measure {
            return "\(Int(grams.rounded())) g \(item.name) · \(measure)"
        }
        if grams >= 50 {
            return "\(Int(grams.rounded())) g \(item.name) · \(String(format: "%.1f", grams / 28.3495)) oz"
        }
        return "\(Int(grams.rounded())) g \(item.name)"
    }
}

/// One cookable meal. Macros are always derived from `components`.
struct HomeMeal: Identifiable, Hashable {
    let id: String
    let name: String
    let cuisine: MealCuisine
    let course: MealCourse
    let method: CookMethod
    let minutes: Int
    let servings: Int
    let components: [MealComponent]
    let steps: [String]
    let tags: Set<MealDietTag>

    /// Per serving.
    var macros: FoodMacros {
        components.reduce(FoodMacros.zero) { $0 + $1.macros }.divided(by: servings)
    }

    var calories: Int { Int(macros.kcal.rounded()) }
    var protein: Int { Int(macros.protein.rounded()) }
    var carbs: Int { Int(macros.carbs.rounded()) }
    var fat: Int { Int(macros.fat.rounded()) }

    /// Grams of protein per 100 kcal — the ratio that actually matters when choosing.
    var proteinDensity: Int {
        guard macros.kcal > 0 else { return 0 }
        return Int((macros.protein / macros.kcal * 100).rounded())
    }

    var subtitle: String {
        "\(cuisine.label) · \(method.label) · \(minutes) min"
    }

    /// Everything a search box should match against.
    var searchIndex: String {
        ([name, cuisine.label, method.label, course.label]
            + tags.map(\.label)
            + components.map(\.item.name)).joined(separator: " ").lowercased()
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: HomeMeal, rhs: HomeMeal) -> Bool { lhs.id == rhs.id }
}

/// A flavour treatment applied on top of a protein/carb/vegetable combination.
struct SeasoningProfile {
    let name: String
    /// Pantry additions that carry the flavour (and their calories).
    let extras: [PantryItem]
    /// Used inside generated method steps.
    let sauceNote: String
}

/// A dish family. The catalogue is the cross product of each blueprint's proteins and
/// carb bases, with the vegetable rotated so neighbouring recipes never look identical.
struct MealBlueprint {
    let key: String
    let cuisine: MealCuisine
    let course: MealCourse
    let method: CookMethod
    let seasoning: SeasoningProfile
    let proteins: [PantryItem]
    let carbs: [PantryItem]
    let vegetables: [PantryItem]
    let minutes: Int
    let servings: Int

    var mealCount: Int { proteins.count * carbs.count }
}
