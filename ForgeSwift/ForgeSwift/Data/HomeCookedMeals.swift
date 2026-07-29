import Foundation

// MARK: - Macro math

/// Nutrition for a quantity of food. All pantry values are stored **per 100 g as served**
/// (cooked for grains and proteins), so scaling is a single multiply and every macro in
/// the catalogue is derived from its ingredients rather than typed in by hand.
struct FoodMacros: Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    static let zero = FoodMacros(kcal: 0, protein: 0, carbs: 0, fat: 0)

    static func + (lhs: FoodMacros, rhs: FoodMacros) -> FoodMacros {
        FoodMacros(
            kcal: lhs.kcal + rhs.kcal,
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }

    /// Scale a per-100 g value to an arbitrary gram amount.
    func forGrams(_ grams: Double) -> FoodMacros {
        let factor = grams / 100
        return FoodMacros(
            kcal: kcal * factor,
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor
        )
    }

    func divided(by servings: Int) -> FoodMacros {
        let d = Double(max(1, servings))
        return FoodMacros(kcal: kcal / d, protein: protein / d, carbs: carbs / d, fat: fat / d)
    }
}

/// Dietary properties carried by an ingredient. Meal-level diet tags are derived by
/// unioning these across the recipe, so a meal can never be mislabelled vegan while
/// containing fish sauce.
enum FoodProperty: String, Hashable {
    case meat        // includes poultry and fish
    case fish
    case animal      // any animal-derived product, including eggs and dairy
    case dairy
    case egg
    case gluten
    case nuts
    case soy
}

// MARK: - Pantry

/// One ingredient with a realistic default portion and per-100 g nutrition.
struct PantryItem: Hashable {
    let key: String
    /// Full name as it appears in an ingredient list.
    let name: String
    /// Short name used when composing a dish title.
    let shortName: String
    /// Portion used per serving, grams as served.
    let grams: Double
    let per100: FoodMacros
    let properties: Set<FoodProperty>
    /// Optional human measure shown alongside grams ("2 large", "1 cup cooked").
    let measure: String?

    init(
        _ key: String,
        name: String,
        short: String? = nil,
        grams: Double,
        kcal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        properties: Set<FoodProperty> = [],
        measure: String? = nil
    ) {
        self.key = key
        self.name = name
        self.shortName = short ?? name
        self.grams = grams
        self.per100 = FoodMacros(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
        self.properties = properties
        self.measure = measure
    }

    func hash(into hasher: inout Hasher) { hasher.combine(key) }
    static func == (lhs: PantryItem, rhs: PantryItem) -> Bool { lhs.key == rhs.key }
}

/// Ingredient reference library. Values follow standard published composition tables for
/// the cooked, edible portion.
enum Pantry {

    // MARK: Proteins

    static let chickenBreast = PantryItem("chickenBreast", name: "chicken breast", short: "Chicken", grams: 170, kcal: 165, protein: 31, carbs: 0, fat: 3.6, properties: [.meat, .animal])
    static let chickenThigh = PantryItem("chickenThigh", name: "boneless chicken thigh", short: "Chicken Thigh", grams: 170, kcal: 209, protein: 26, carbs: 0, fat: 10.9, properties: [.meat, .animal])
    static let groundChicken = PantryItem("groundChicken", name: "ground chicken", short: "Ground Chicken", grams: 150, kcal: 189, protein: 24, carbs: 0, fat: 10, properties: [.meat, .animal])
    static let turkeyBreast = PantryItem("turkeyBreast", name: "turkey breast", short: "Turkey", grams: 170, kcal: 135, protein: 30, carbs: 0, fat: 1, properties: [.meat, .animal])
    static let groundTurkey = PantryItem("groundTurkey", name: "93% lean ground turkey", short: "Ground Turkey", grams: 150, kcal: 176, protein: 27, carbs: 0, fat: 7, properties: [.meat, .animal])
    static let groundBeef = PantryItem("groundBeef", name: "90/10 ground beef", short: "Beef", grams: 150, kcal: 217, protein: 26, carbs: 0, fat: 11.7, properties: [.meat, .animal])
    static let sirloin = PantryItem("sirloin", name: "sirloin steak", short: "Steak", grams: 150, kcal: 206, protein: 30, carbs: 0, fat: 9, properties: [.meat, .animal])
    static let porkTenderloin = PantryItem("porkTenderloin", name: "pork tenderloin", short: "Pork", grams: 160, kcal: 143, protein: 26, carbs: 0, fat: 3.5, properties: [.meat, .animal])
    static let lamb = PantryItem("lamb", name: "lamb loin", short: "Lamb", grams: 150, kcal: 202, protein: 26, carbs: 0, fat: 10, properties: [.meat, .animal])
    static let groundLamb = PantryItem("groundLamb", name: "ground lamb", short: "Ground Lamb", grams: 140, kcal: 283, protein: 25, carbs: 0, fat: 20, properties: [.meat, .animal])
    static let salmon = PantryItem("salmon", name: "salmon fillet", short: "Salmon", grams: 170, kcal: 208, protein: 22, carbs: 0, fat: 13, properties: [.meat, .fish, .animal])
    static let cod = PantryItem("cod", name: "cod fillet", short: "Cod", grams: 180, kcal: 105, protein: 23, carbs: 0, fat: 0.9, properties: [.meat, .fish, .animal])
    static let tilapia = PantryItem("tilapia", name: "tilapia fillet", short: "Tilapia", grams: 170, kcal: 128, protein: 26, carbs: 0, fat: 2.7, properties: [.meat, .fish, .animal])
    static let shrimp = PantryItem("shrimp", name: "shrimp", short: "Shrimp", grams: 170, kcal: 99, protein: 24, carbs: 0.2, fat: 0.3, properties: [.meat, .fish, .animal])
    static let scallops = PantryItem("scallops", name: "sea scallops", short: "Scallop", grams: 150, kcal: 111, protein: 20, carbs: 5, fat: 0.8, properties: [.meat, .fish, .animal])
    static let mussels = PantryItem("mussels", name: "mussels", short: "Mussel", grams: 150, kcal: 172, protein: 24, carbs: 7, fat: 4.5, properties: [.meat, .fish, .animal])
    static let cannedTuna = PantryItem("cannedTuna", name: "canned tuna in water", short: "Tuna", grams: 140, kcal: 116, protein: 26, carbs: 0, fat: 0.8, properties: [.meat, .fish, .animal])
    static let eggs = PantryItem("eggs", name: "eggs", short: "Egg", grams: 110, kcal: 155, protein: 13, carbs: 1.1, fat: 11, properties: [.egg, .animal], measure: "2 large")
    static let eggWhites = PantryItem("eggWhites", name: "egg whites", short: "Egg White", grams: 200, kcal: 52, protein: 11, carbs: 0.7, fat: 0.2, properties: [.egg, .animal], measure: "about 6")
    static let greekYogurt = PantryItem("greekYogurt", name: "non-fat Greek yogurt", short: "Greek Yogurt", grams: 200, kcal: 59, protein: 10, carbs: 3.6, fat: 0.4, properties: [.dairy, .animal], measure: "1 cup")
    static let cottageCheese = PantryItem("cottageCheese", name: "2% cottage cheese", short: "Cottage Cheese", grams: 180, kcal: 84, protein: 11, carbs: 4.3, fat: 2.3, properties: [.dairy, .animal], measure: "¾ cup")
    static let wheyProtein = PantryItem("wheyProtein", name: "whey protein powder", short: "Protein", grams: 32, kcal: 375, protein: 78, carbs: 8, fat: 4, properties: [.dairy, .animal], measure: "1 scoop")
    static let tofu = PantryItem("tofu", name: "extra-firm tofu", short: "Tofu", grams: 170, kcal: 144, protein: 17, carbs: 3, fat: 9, properties: [.soy])
    static let tempeh = PantryItem("tempeh", name: "tempeh", short: "Tempeh", grams: 140, kcal: 192, protein: 20, carbs: 8, fat: 11, properties: [.soy])
    static let seitan = PantryItem("seitan", name: "seitan", short: "Seitan", grams: 140, kcal: 143, protein: 25, carbs: 14, fat: 1.9, properties: [.gluten])
    static let edamame = PantryItem("edamame", name: "shelled edamame", short: "Edamame", grams: 160, kcal: 122, protein: 11, carbs: 10, fat: 5, properties: [.soy])
    static let chickpeas = PantryItem("chickpeas", name: "cooked chickpeas", short: "Chickpea", grams: 180, kcal: 164, protein: 9, carbs: 27, fat: 2.6)
    static let blackBeans = PantryItem("blackBeans", name: "cooked black beans", short: "Black Bean", grams: 180, kcal: 132, protein: 9, carbs: 24, fat: 0.5)
    static let whiteBeans = PantryItem("whiteBeans", name: "cooked cannellini beans", short: "White Bean", grams: 180, kcal: 139, protein: 10, carbs: 25, fat: 0.5)
    static let lentils = PantryItem("lentils", name: "cooked brown lentils", short: "Lentil", grams: 190, kcal: 116, protein: 9, carbs: 20, fat: 0.4)
    static let paneer = PantryItem("paneer", name: "paneer", short: "Paneer", grams: 120, kcal: 296, protein: 20, carbs: 3.6, fat: 22, properties: [.dairy, .animal])
    static let halloumi = PantryItem("halloumi", name: "halloumi", short: "Halloumi", grams: 110, kcal: 321, protein: 22, carbs: 2.2, fat: 25, properties: [.dairy, .animal])

    // MARK: Carb bases

    static let jasmineRice = PantryItem("jasmineRice", name: "cooked jasmine rice", short: "Jasmine Rice", grams: 180, kcal: 130, protein: 2.7, carbs: 28, fat: 0.3, measure: "1 cup")
    static let brownRice = PantryItem("brownRice", name: "cooked brown rice", short: "Brown Rice", grams: 180, kcal: 123, protein: 2.7, carbs: 26, fat: 1, measure: "1 cup")
    static let quinoa = PantryItem("quinoa", name: "cooked quinoa", short: "Quinoa", grams: 170, kcal: 120, protein: 4.4, carbs: 21, fat: 1.9, measure: "1 cup")
    static let couscous = PantryItem("couscous", name: "cooked couscous", short: "Couscous", grams: 170, kcal: 112, protein: 3.8, carbs: 23, fat: 0.2, properties: [.gluten])
    static let farro = PantryItem("farro", name: "cooked farro", short: "Farro", grams: 170, kcal: 130, protein: 5, carbs: 26, fat: 1, properties: [.gluten])
    static let barley = PantryItem("barley", name: "cooked pearl barley", short: "Barley", grams: 170, kcal: 123, protein: 2.3, carbs: 28, fat: 0.4, properties: [.gluten])
    static let wholeWheatPasta = PantryItem("wholeWheatPasta", name: "cooked whole-wheat pasta", short: "Whole-Wheat Pasta", grams: 180, kcal: 124, protein: 5.3, carbs: 27, fat: 0.5, properties: [.gluten])
    static let chickpeaPasta = PantryItem("chickpeaPasta", name: "cooked chickpea pasta", short: "Chickpea Pasta", grams: 170, kcal: 150, protein: 9, carbs: 25, fat: 2.5)
    static let soba = PantryItem("soba", name: "cooked soba noodles", short: "Soba", grams: 170, kcal: 99, protein: 5.1, carbs: 21, fat: 0.1, properties: [.gluten])
    static let riceNoodles = PantryItem("riceNoodles", name: "cooked rice noodles", short: "Rice Noodle", grams: 180, kcal: 109, protein: 0.9, carbs: 25, fat: 0.2)
    static let sweetPotato = PantryItem("sweetPotato", name: "roasted sweet potato", short: "Sweet Potato", grams: 200, kcal: 90, protein: 2, carbs: 21, fat: 0.2)
    static let babyPotato = PantryItem("babyPotato", name: "roasted baby potatoes", short: "Roast Potato", grams: 200, kcal: 93, protein: 2.5, carbs: 20, fat: 0.6)
    static let polenta = PantryItem("polenta", name: "soft polenta", short: "Polenta", grams: 200, kcal: 85, protein: 2, carbs: 18, fat: 0.4)
    static let cornTortillas = PantryItem("cornTortillas", name: "corn tortillas", short: "Corn Tortilla", grams: 90, kcal: 218, protein: 5.7, carbs: 45, fat: 2.9, measure: "3 small")
    static let pita = PantryItem("pita", name: "whole-wheat pita", short: "Pita", grams: 70, kcal: 275, protein: 9, carbs: 55, fat: 2.7, properties: [.gluten], measure: "1 round")
    static let cauliflowerRice = PantryItem("cauliflowerRice", name: "cauliflower rice", short: "Cauliflower Rice", grams: 200, kcal: 25, protein: 2, carbs: 5, fat: 0.3)
    static let oatmeal = PantryItem("oatmeal", name: "cooked rolled oats", short: "Oats", grams: 250, kcal: 71, protein: 2.5, carbs: 12, fat: 1.5, properties: [.gluten], measure: "1 cup")
    static let sourdough = PantryItem("sourdough", name: "whole-grain sourdough", short: "Sourdough", grams: 80, kcal: 250, protein: 10, carbs: 46, fat: 2.5, properties: [.gluten], measure: "2 slices")

    // MARK: Vegetables

    static let broccoli = PantryItem("broccoli", name: "broccoli florets", short: "Broccoli", grams: 150, kcal: 35, protein: 2.4, carbs: 7, fat: 0.4)
    static let greenBeans = PantryItem("greenBeans", name: "green beans", short: "Green Beans", grams: 150, kcal: 35, protein: 1.9, carbs: 8, fat: 0.2)
    static let bellPepper = PantryItem("bellPepper", name: "bell peppers", short: "Bell Pepper", grams: 150, kcal: 26, protein: 1, carbs: 6, fat: 0.3)
    static let zucchini = PantryItem("zucchini", name: "zucchini", short: "Zucchini", grams: 150, kcal: 17, protein: 1.2, carbs: 3.1, fat: 0.3)
    static let asparagus = PantryItem("asparagus", name: "asparagus", short: "Asparagus", grams: 140, kcal: 22, protein: 2.4, carbs: 4, fat: 0.2)
    static let spinach = PantryItem("spinach", name: "baby spinach", short: "Spinach", grams: 120, kcal: 23, protein: 2.9, carbs: 3.6, fat: 0.4)
    static let kale = PantryItem("kale", name: "kale", short: "Kale", grams: 120, kcal: 35, protein: 2.9, carbs: 4.4, fat: 1.5)
    static let brusselsSprouts = PantryItem("brusselsSprouts", name: "Brussels sprouts", short: "Brussels Sprout", grams: 150, kcal: 43, protein: 3.4, carbs: 9, fat: 0.3)
    static let mushrooms = PantryItem("mushrooms", name: "cremini mushrooms", short: "Mushroom", grams: 150, kcal: 22, protein: 3.1, carbs: 3.3, fat: 0.3)
    static let cherryTomatoes = PantryItem("cherryTomatoes", name: "cherry tomatoes", short: "Cherry Tomato", grams: 150, kcal: 18, protein: 0.9, carbs: 3.9, fat: 0.2)
    static let carrots = PantryItem("carrots", name: "carrots", short: "Carrot", grams: 140, kcal: 41, protein: 0.9, carbs: 10, fat: 0.2)
    static let cauliflower = PantryItem("cauliflower", name: "cauliflower", short: "Cauliflower", grams: 150, kcal: 25, protein: 1.9, carbs: 5, fat: 0.3)
    static let snapPeas = PantryItem("snapPeas", name: "sugar snap peas", short: "Snap Pea", grams: 140, kcal: 42, protein: 2.8, carbs: 7.5, fat: 0.2)
    static let bokChoy = PantryItem("bokChoy", name: "bok choy", short: "Bok Choy", grams: 150, kcal: 13, protein: 1.5, carbs: 2.2, fat: 0.2)
    static let cabbage = PantryItem("cabbage", name: "shredded cabbage", short: "Cabbage", grams: 140, kcal: 25, protein: 1.3, carbs: 6, fat: 0.1)
    static let eggplant = PantryItem("eggplant", name: "eggplant", short: "Eggplant", grams: 150, kcal: 25, protein: 1, carbs: 6, fat: 0.2)
    static let redOnion = PantryItem("redOnion", name: "red onion", short: "Red Onion", grams: 100, kcal: 40, protein: 1.1, carbs: 9, fat: 0.1)
    static let corn = PantryItem("corn", name: "sweet corn", short: "Corn", grams: 130, kcal: 96, protein: 3.4, carbs: 21, fat: 1.5)
    static let butternut = PantryItem("butternut", name: "butternut squash", short: "Butternut", grams: 170, kcal: 45, protein: 1, carbs: 12, fat: 0.1)
    static let cucumber = PantryItem("cucumber", name: "cucumber", short: "Cucumber", grams: 140, kcal: 15, protein: 0.7, carbs: 3.6, fat: 0.1)
    static let romaine = PantryItem("romaine", name: "romaine lettuce", short: "Romaine", grams: 120, kcal: 17, protein: 1.2, carbs: 3.3, fat: 0.3)
    static let berries = PantryItem("berries", name: "mixed berries", short: "Berry", grams: 140, kcal: 50, protein: 0.8, carbs: 12, fat: 0.3)
    static let banana = PantryItem("banana", name: "banana", short: "Banana", grams: 120, kcal: 89, protein: 1.1, carbs: 23, fat: 0.3, measure: "1 medium")

    // MARK: Fats, sauces and finishing

    static let oliveOil = PantryItem("oliveOil", name: "olive oil", grams: 14, kcal: 884, protein: 0, carbs: 0, fat: 100, measure: "1 tbsp")
    static let sesameOil = PantryItem("sesameOil", name: "toasted sesame oil", grams: 9, kcal: 884, protein: 0, carbs: 0, fat: 100, measure: "2 tsp")
    static let butter = PantryItem("butter", name: "butter", grams: 10, kcal: 717, protein: 0.9, carbs: 0.1, fat: 81, properties: [.dairy, .animal], measure: "2 tsp")
    static let avocado = PantryItem("avocado", name: "avocado", grams: 60, kcal: 160, protein: 2, carbs: 9, fat: 15, measure: "½ small")
    static let tahini = PantryItem("tahini", name: "tahini", grams: 20, kcal: 595, protein: 17, carbs: 21, fat: 54, properties: [.nuts], measure: "1 tbsp")
    static let peanutButter = PantryItem("peanutButter", name: "natural peanut butter", grams: 24, kcal: 588, protein: 25, carbs: 20, fat: 50, properties: [.nuts], measure: "1½ tbsp")
    static let coconutMilk = PantryItem("coconutMilk", name: "light coconut milk", grams: 100, kcal: 197, protein: 2, carbs: 3, fat: 21, measure: "⅓ cup")
    static let feta = PantryItem("feta", name: "feta", grams: 30, kcal: 264, protein: 14, carbs: 4, fat: 21, properties: [.dairy, .animal])
    static let parmesan = PantryItem("parmesan", name: "grated Parmesan", grams: 15, kcal: 392, protein: 36, carbs: 3, fat: 25, properties: [.dairy, .animal], measure: "2 tbsp")
    static let almonds = PantryItem("almonds", name: "toasted almonds", grams: 15, kcal: 579, protein: 21, carbs: 22, fat: 50, properties: [.nuts])
    static let cashews = PantryItem("cashews", name: "roasted cashews", grams: 18, kcal: 553, protein: 18, carbs: 30, fat: 44, properties: [.nuts])
    static let sesameSeeds = PantryItem("sesameSeeds", name: "sesame seeds", grams: 8, kcal: 573, protein: 18, carbs: 23, fat: 50, measure: "1 tbsp")
    static let pesto = PantryItem("pesto", name: "basil pesto", grams: 25, kcal: 450, protein: 5, carbs: 6, fat: 45, properties: [.dairy, .nuts, .animal], measure: "1½ tbsp")
    static let soySauce = PantryItem("soySauce", name: "low-sodium soy sauce", grams: 18, kcal: 53, protein: 8, carbs: 5, fat: 0.1, properties: [.soy, .gluten], measure: "1 tbsp")
    static let passata = PantryItem("passata", name: "tomato passata", grams: 150, kcal: 35, protein: 1.6, carbs: 7, fat: 0.3, measure: "⅔ cup")
    static let curryPaste = PantryItem("curryPaste", name: "curry paste", grams: 25, kcal: 100, protein: 3, carbs: 15, fat: 3)
    static let salsa = PantryItem("salsa", name: "tomato salsa", grams: 70, kcal: 36, protein: 1.5, carbs: 7, fat: 0.2, measure: "¼ cup")
    static let harissa = PantryItem("harissa", name: "harissa paste", grams: 20, kcal: 130, protein: 3, carbs: 12, fat: 8, measure: "1 tbsp")
    static let gochujang = PantryItem("gochujang", name: "gochujang", grams: 20, kcal: 214, protein: 6, carbs: 45, fat: 1.4, properties: [.gluten, .soy], measure: "1 tbsp")
    static let miso = PantryItem("miso", name: "white miso", grams: 18, kcal: 199, protein: 12, carbs: 26, fat: 6, properties: [.soy], measure: "1 tbsp")
    static let lemon = PantryItem("lemon", name: "lemon juice + zest", grams: 20, kcal: 22, protein: 0.4, carbs: 7, fat: 0.2, measure: "½ lemon")
    static let lime = PantryItem("lime", name: "lime juice", grams: 15, kcal: 25, protein: 0.4, carbs: 8, fat: 0.2, measure: "½ lime")
    static let honey = PantryItem("honey", name: "honey", grams: 12, kcal: 304, protein: 0.3, carbs: 82, fat: 0, properties: [.animal], measure: "2 tsp")
    static let maple = PantryItem("maple", name: "maple syrup", grams: 12, kcal: 260, protein: 0, carbs: 67, fat: 0.1, measure: "2 tsp")
    static let garlicGinger = PantryItem("garlicGinger", name: "garlic + fresh ginger", grams: 15, kcal: 120, protein: 5, carbs: 25, fat: 0.5, measure: "3 cloves + 1 in")
    static let herbs = PantryItem("herbs", name: "fresh herbs", grams: 12, kcal: 40, protein: 3, carbs: 7, fat: 0.7, measure: "small handful")
    static let spiceBlend = PantryItem("spiceBlend", name: "spice blend", grams: 6, kcal: 250, protein: 10, carbs: 45, fat: 8, measure: "2 tsp")
    static let chiliCrisp = PantryItem("chiliCrisp", name: "chili crisp", grams: 15, kcal: 500, protein: 6, carbs: 12, fat: 50, measure: "1 tbsp")
}

// MARK: - Taxonomy

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

// MARK: - Recipe

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

// MARK: - Blueprints

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

// MARK: - Catalogue

enum HomeCookedMeals {

    /// Every generated meal, built once on first access.
    static let all: [HomeMeal] = blueprints.flatMap(expand)

    static var count: Int { all.count }

    /// Fast lookup for deep links and logging round-trips.
    static let byID: [String: HomeMeal] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    // MARK: Expansion

    private static func expand(_ blueprint: MealBlueprint) -> [HomeMeal] {
        var meals: [HomeMeal] = []
        meals.reserveCapacity(blueprint.mealCount)
        for (proteinIndex, protein) in blueprint.proteins.enumerated() {
            for (carbIndex, carb) in blueprint.carbs.enumerated() {
                let rotation = proteinIndex * blueprint.carbs.count + carbIndex
                let vegetable = blueprint.vegetables[rotation % blueprint.vegetables.count]
                meals.append(
                    make(blueprint: blueprint, protein: protein, carb: carb, vegetable: vegetable)
                )
            }
        }
        return meals
    }

    private static func make(
        blueprint: MealBlueprint,
        protein: PantryItem,
        carb: PantryItem,
        vegetable: PantryItem
    ) -> HomeMeal {
        var components: [MealComponent] = [
            MealComponent(item: protein, grams: protein.grams),
            MealComponent(item: carb, grams: carb.grams),
            MealComponent(item: vegetable, grams: vegetable.grams),
        ]
        components += blueprint.seasoning.extras.map { MealComponent(item: $0, grams: $0.grams) }

        let name = "\(blueprint.seasoning.name) \(protein.shortName) \(blueprint.method.label) with \(carb.shortName) & \(vegetable.shortName)"
        let id = "\(blueprint.key).\(protein.key).\(carb.key).\(vegetable.key)"

        let meal = HomeMeal(
            id: id,
            name: name,
            cuisine: blueprint.cuisine,
            course: blueprint.course,
            method: blueprint.method,
            minutes: blueprint.minutes,
            servings: blueprint.servings,
            components: components,
            steps: steps(
                method: blueprint.method,
                seasoning: blueprint.seasoning,
                protein: protein,
                carb: carb,
                vegetable: vegetable
            ),
            tags: []
        )
        return HomeMeal(
            id: meal.id,
            name: meal.name,
            cuisine: meal.cuisine,
            course: meal.course,
            method: meal.method,
            minutes: meal.minutes,
            servings: meal.servings,
            components: components,
            steps: meal.steps,
            tags: derivedTags(for: meal, components: components, method: blueprint.method, minutes: blueprint.minutes)
        )
    }

    /// Diet tags are computed from the actual ingredient set, so they cannot drift from
    /// the recipe the way hand-typed labels do.
    private static func derivedTags(
        for meal: HomeMeal,
        components: [MealComponent],
        method: CookMethod,
        minutes: Int
    ) -> Set<MealDietTag> {
        let properties = components.reduce(into: Set<FoodProperty>()) { $0.formUnion($1.item.properties) }
        var tags: Set<MealDietTag> = []

        if !properties.contains(.animal) && !properties.contains(.meat) { tags.insert(.vegan) }
        if !properties.contains(.meat) { tags.insert(.vegetarian) }
        if !properties.contains(.gluten) { tags.insert(.glutenFree) }
        if !properties.contains(.dairy) { tags.insert(.dairyFree) }
        if !properties.contains(.nuts) { tags.insert(.nutFree) }

        let macros = meal.macros
        if macros.protein >= 30, macros.kcal > 0, (macros.protein * 4 / macros.kcal) >= 0.25 {
            tags.insert(.highProtein)
        }
        if macros.carbs <= 30 { tags.insert(.lowCarb) }
        if minutes <= 30 { tags.insert(.quick) }
        if method.isMealPrepFriendly { tags.insert(.mealPrep) }
        return tags
    }

    // MARK: Method steps

    private static func steps(
        method: CookMethod,
        seasoning: SeasoningProfile,
        protein: PantryItem,
        carb: PantryItem,
        vegetable: PantryItem
    ) -> [String] {
        let p = protein.name
        let c = carb.name
        let v = vegetable.name
        let sauce = seasoning.sauceNote

        switch method {
        case .sheetPan, .bake:
            return [
                "Heat the oven to 220 °C / 425 °F and line a large sheet pan.",
                "Toss the \(v) with half the oil, salt and pepper. Spread to one side of the pan.",
                "Pat the \(p) dry, coat it in \(sauce) and set it on the other side so nothing steams.",
                "Roast 18–22 minutes, until the \(v) is browned at the edges and the \(p) is cooked through.",
                "Meanwhile warm the \(c). Plate the \(c) first, add the \(p) and \(v), and spoon over any pan juices.",
            ]
        case .stirFry:
            return [
                "Have everything cut and within arm's reach before the pan gets hot — a stir-fry gives you no time to chop.",
                "Get a wok or wide skillet ripping hot, add the oil, then the \(p) in a single layer. Leave it 60 seconds to sear before moving it.",
                "Push the \(p) to the side, add the \(v) and stir-fry 2–3 minutes until it's bright and barely tender.",
                "Pour in \(sauce), toss for 30–60 seconds until it glazes everything, then kill the heat.",
                "Serve over the \(c) while it's still steaming.",
            ]
        case .curry:
            return [
                "Warm the oil in a heavy pot and fry \(sauce) for 1–2 minutes until it smells fragrant.",
                "Add the \(p) and turn it to coat in the paste.",
                "Pour in the liquid, bring to a gentle simmer and cook 12–15 minutes.",
                "Add the \(v) in the last 5 minutes so it keeps its bite.",
                "Taste for salt, acid and heat — adjust all three. Serve over the \(c).",
            ]
        case .skillet:
            return [
                "Season the \(p) generously and let it sit while the pan heats.",
                "Sear the \(p) in a hot skillet, undisturbed, until it releases cleanly — about 4 minutes a side.",
                "Rest the \(p) on a board. In the same pan, cook the \(v) in the fond left behind.",
                "Add \(sauce) and swirl to pull up everything stuck to the pan.",
                "Slice the \(p), return it to the pan with the \(c), and toss once to combine.",
            ]
        case .grill, .skewers:
            return [
                "Marinate the \(p) in \(sauce) for at least 20 minutes — longer if you have it.",
                "Heat the grill to medium-high and oil the grates.",
                "Grill the \(p) until charred and cooked through, turning once. Rest it 5 minutes before slicing.",
                "Grill the \(v) alongside until it takes on colour.",
                "Serve over the \(c) with the resting juices poured back over.",
            ]
        case .braise, .slowCooker:
            return [
                "Brown the \(p) hard on all sides — this is where the flavour comes from, so don't rush it.",
                "Add \(sauce) and enough liquid to come halfway up the \(p).",
                "Cover and cook low and slow until the \(p) gives easily to a fork.",
                "Add the \(v) for the final stretch so it doesn't collapse.",
                "Skim the fat, adjust seasoning, and serve over the \(c).",
            ]
        case .soup:
            return [
                "Sweat the aromatics in oil until soft and translucent.",
                "Stir in \(sauce), then add the \(p) and enough stock to cover.",
                "Simmer gently 20–25 minutes.",
                "Add the \(v) and the \(c) and cook until just tender.",
                "Finish with acid and fresh herbs — soup almost always needs more of both than you think.",
            ]
        case .salad:
            return [
                "Cook and cool the \(c) so it doesn't wilt everything it touches.",
                "Cook or drain the \(p) and season it while it's still warm — that's when it absorbs the most.",
                "Whisk \(sauce) into a dressing that tastes slightly too sharp on its own.",
                "Toss the \(v) and \(c) with two-thirds of the dressing.",
                "Top with the \(p), spoon over the rest of the dressing, and serve immediately.",
            ]
        case .bowl, .poke:
            return [
                "Cook the \(c) and spread it in a wide bowl to cool slightly.",
                "Season and cook the \(p) to your liking, then slice or flake it.",
                "Prepare the \(v) — raw and crisp, or quickly blanched.",
                "Whisk \(sauce) until pourable.",
                "Build in sections rather than stirring, so every bite can be composed differently. Sauce last.",
            ]
        case .taco, .wrap:
            return [
                "Cook the \(p) with \(sauce) until deeply browned and saucy, not wet.",
                "Warm the \(c) directly over a flame or in a dry pan until pliable and blistered.",
                "Shred or slice the \(v) thin so it stays crunchy.",
                "Fill, but don't overfill — structural failure is the enemy.",
                "Finish with lime, fresh herbs and something sharp to cut the richness.",
            ]
        case .pasta:
            return [
                "Salt the pasta water until it tastes like the sea, then cook the \(c) one minute short of the box time.",
                "While it cooks, brown the \(p) in a wide pan.",
                "Add the \(v) and \(sauce), and let it reduce slightly.",
                "Reserve a mug of pasta water, drain, and finish the \(c) in the pan with a splash of that water.",
                "Toss hard for 30 seconds — the starch is what makes the sauce cling.",
            ]
        case .chili:
            return [
                "Brown the \(p) in a heavy pot and don't stir it too early.",
                "Add \(sauce) and toast the spices in the fat for a full minute.",
                "Add tomatoes and stock, then simmer at least 40 minutes — longer is better.",
                "Stir in the \(v) toward the end.",
                "Serve over the \(c) with something cold and creamy on top.",
            ]
        case .airFryer:
            return [
                "Heat the air fryer to 200 °C / 400 °F.",
                "Toss the \(p) with \(sauce) and a little oil.",
                "Cook 10–14 minutes, shaking the basket halfway, until crisp at the edges.",
                "Air-fry the \(v) in a second batch — crowding is what makes things soggy.",
                "Serve over the \(c).",
            ]
        case .noodleBowl:
            return [
                "Bring the broth to a simmer with \(sauce) and let it infuse while you work.",
                "Cook the \(c) separately and rinse it so it doesn't cloud the broth.",
                "Poach or sear the \(p) and slice it thin against the grain.",
                "Blanch the \(v) for 30 seconds.",
                "Assemble noodles, \(p) and \(v) in the bowl, then pour the hot broth over at the table.",
            ]
        case .hash:
            return [
                "Get the \(c) crisping in a hot, oiled pan and then leave it alone — moving it is why hash goes mushy.",
                "Add the \(p) and \(sauce), breaking it up as it browns.",
                "Stir through the \(v) and cook until it just softens.",
                "Make wells in the hash and crack in eggs if you want them, then cover until set.",
                "Finish with hot sauce and something fresh.",
            ]
        case .frittata:
            return [
                "Heat the oven to 190 °C / 375 °F.",
                "Cook the \(v) and \(c) in an oven-safe skillet until any moisture has cooked off.",
                "Add the \(p) and \(sauce), then pour over the beaten eggs.",
                "Cook on the hob until the edges set, then move the pan to the oven for 10–12 minutes.",
                "Let it stand 5 minutes before slicing — it firms up as it rests.",
            ]
        case .porridge:
            return [
                "Cook the \(c) with a pinch of salt until creamy — salt is the difference between porridge and wallpaper paste.",
                "Stir the \(p) in off the heat so it stays smooth and doesn't split.",
                "Fold through \(sauce).",
                "Top with the \(v).",
                "Eat straight away, while the texture is still loose.",
            ]
        case .congee:
            return [
                "Simmer the \(c) in plenty of stock, stirring occasionally, until it breaks down into a loose porridge.",
                "Add the \(p) in the last 10 minutes so it stays tender.",
                "Season with \(sauce).",
                "Wilt the \(v) through at the very end.",
                "Serve with crunchy toppings — congee needs contrast.",
            ]
        }
    }

    // MARK: Blueprint table

    private static let blueprints: [MealBlueprint] = [

        // ---- American ----
        MealBlueprint(
            key: "sheetpan",
            cuisine: .american, course: .dinner, method: .sheetPan,
            seasoning: SeasoningProfile(name: "Garlic-Herb", extras: [Pantry.oliveOil, Pantry.herbs, Pantry.lemon], sauceNote: "garlic, herbs and olive oil"),
            proteins: [Pantry.chickenBreast, Pantry.chickenThigh, Pantry.salmon, Pantry.cod, Pantry.porkTenderloin, Pantry.tofu],
            carbs: [Pantry.babyPotato, Pantry.sweetPotato, Pantry.brownRice, Pantry.farro, Pantry.quinoa],
            vegetables: [Pantry.broccoli, Pantry.brusselsSprouts, Pantry.asparagus, Pantry.carrots, Pantry.greenBeans, Pantry.cauliflower, Pantry.butternut],
            minutes: 40, servings: 2
        ),
        MealBlueprint(
            key: "chili",
            cuisine: .american, course: .dinner, method: .chili,
            seasoning: SeasoningProfile(name: "Smoky", extras: [Pantry.oliveOil, Pantry.passata, Pantry.spiceBlend], sauceNote: "smoked paprika, cumin and chipotle"),
            proteins: [Pantry.groundBeef, Pantry.groundTurkey, Pantry.blackBeans, Pantry.lentils, Pantry.groundChicken, Pantry.whiteBeans],
            carbs: [Pantry.brownRice, Pantry.sweetPotato, Pantry.polenta, Pantry.barley, Pantry.jasmineRice],
            vegetables: [Pantry.bellPepper, Pantry.redOnion, Pantry.corn, Pantry.mushrooms, Pantry.zucchini, Pantry.carrots],
            minutes: 55, servings: 4
        ),
        MealBlueprint(
            key: "soup",
            cuisine: .american, course: .lunch, method: .soup,
            seasoning: SeasoningProfile(name: "Hearty", extras: [Pantry.oliveOil, Pantry.herbs, Pantry.lemon], sauceNote: "thyme, bay and cracked pepper"),
            proteins: [Pantry.chickenBreast, Pantry.lentils, Pantry.whiteBeans, Pantry.turkeyBreast, Pantry.chickpeas, Pantry.groundTurkey],
            carbs: [Pantry.barley, Pantry.brownRice, Pantry.wholeWheatPasta, Pantry.babyPotato, Pantry.farro],
            vegetables: [Pantry.carrots, Pantry.kale, Pantry.spinach, Pantry.mushrooms, Pantry.cabbage, Pantry.greenBeans],
            minutes: 45, servings: 4
        ),
        MealBlueprint(
            key: "airfryer",
            cuisine: .american, course: .dinner, method: .airFryer,
            seasoning: SeasoningProfile(name: "Crispy Paprika", extras: [Pantry.oliveOil, Pantry.spiceBlend], sauceNote: "smoked paprika and garlic powder"),
            proteins: [Pantry.chickenBreast, Pantry.tofu, Pantry.cod, Pantry.shrimp, Pantry.chickenThigh, Pantry.tempeh],
            carbs: [Pantry.sweetPotato, Pantry.babyPotato, Pantry.brownRice, Pantry.quinoa, Pantry.cauliflowerRice],
            vegetables: [Pantry.broccoli, Pantry.greenBeans, Pantry.brusselsSprouts, Pantry.cauliflower, Pantry.zucchini, Pantry.bellPepper],
            minutes: 25, servings: 2
        ),
        MealBlueprint(
            key: "slowcooker",
            cuisine: .american, course: .dinner, method: .slowCooker,
            seasoning: SeasoningProfile(name: "Slow-Braised", extras: [Pantry.oliveOil, Pantry.passata, Pantry.herbs], sauceNote: "tomato, stock and bay"),
            proteins: [Pantry.sirloin, Pantry.chickenThigh, Pantry.lentils, Pantry.blackBeans, Pantry.porkTenderloin, Pantry.whiteBeans],
            carbs: [Pantry.brownRice, Pantry.barley, Pantry.babyPotato, Pantry.polenta, Pantry.sweetPotato],
            vegetables: [Pantry.carrots, Pantry.mushrooms, Pantry.kale, Pantry.cabbage, Pantry.butternut, Pantry.redOnion],
            minutes: 240, servings: 4
        ),
        MealBlueprint(
            key: "smashbowl",
            cuisine: .american, course: .dinner, method: .bowl,
            seasoning: SeasoningProfile(name: "Special-Sauce", extras: [Pantry.oliveOil, Pantry.greekYogurt, Pantry.spiceBlend], sauceNote: "yogurt, mustard and pickle brine"),
            proteins: [Pantry.groundBeef, Pantry.groundTurkey, Pantry.groundChicken, Pantry.tempeh, Pantry.blackBeans, Pantry.tofu],
            carbs: [Pantry.babyPotato, Pantry.sweetPotato, Pantry.brownRice, Pantry.quinoa, Pantry.wholeWheatPasta],
            vegetables: [Pantry.romaine, Pantry.cherryTomatoes, Pantry.redOnion, Pantry.cabbage, Pantry.cucumber, Pantry.bellPepper],
            minutes: 30, servings: 2
        ),
        MealBlueprint(
            key: "buffalo",
            cuisine: .american, course: .lunch, method: .salad,
            seasoning: SeasoningProfile(name: "Buffalo-Ranch", extras: [Pantry.greekYogurt, Pantry.oliveOil, Pantry.spiceBlend], sauceNote: "hot sauce whisked into yogurt with dill"),
            proteins: [Pantry.chickenBreast, Pantry.tofu, Pantry.chickpeas, Pantry.shrimp, Pantry.turkeyBreast, Pantry.tempeh],
            carbs: [Pantry.quinoa, Pantry.brownRice, Pantry.sweetPotato, Pantry.barley, Pantry.babyPotato],
            vegetables: [Pantry.romaine, Pantry.carrots, Pantry.cabbage, Pantry.cherryTomatoes, Pantry.bellPepper, Pantry.broccoli],
            minutes: 25, servings: 2
        ),
        MealBlueprint(
            key: "hash",
            cuisine: .american, course: .breakfast, method: .hash,
            seasoning: SeasoningProfile(name: "Skillet", extras: [Pantry.oliveOil, Pantry.spiceBlend, Pantry.salsa], sauceNote: "paprika, garlic and a spoon of salsa"),
            proteins: [Pantry.eggs, Pantry.groundTurkey, Pantry.tofu, Pantry.chickenBreast, Pantry.blackBeans, Pantry.tempeh],
            carbs: [Pantry.sweetPotato, Pantry.babyPotato, Pantry.brownRice, Pantry.quinoa, Pantry.cornTortillas],
            vegetables: [Pantry.bellPepper, Pantry.spinach, Pantry.mushrooms, Pantry.kale, Pantry.redOnion, Pantry.zucchini],
            minutes: 25, servings: 2
        ),
        MealBlueprint(
            key: "porridge",
            cuisine: .american, course: .breakfast, method: .porridge,
            seasoning: SeasoningProfile(name: "Cinnamon", extras: [Pantry.peanutButter, Pantry.maple], sauceNote: "cinnamon, nut butter and a little maple"),
            proteins: [Pantry.greekYogurt, Pantry.cottageCheese, Pantry.wheyProtein, Pantry.eggWhites, Pantry.eggs, Pantry.tofu],
            carbs: [Pantry.oatmeal, Pantry.quinoa, Pantry.barley, Pantry.brownRice, Pantry.sourdough],
            vegetables: [Pantry.berries, Pantry.banana],
            minutes: 15, servings: 1
        ),

        // ---- Mexican ----
        MealBlueprint(
            key: "tacos",
            cuisine: .mexican, course: .dinner, method: .taco,
            seasoning: SeasoningProfile(name: "Chipotle-Lime", extras: [Pantry.oliveOil, Pantry.lime, Pantry.spiceBlend, Pantry.salsa], sauceNote: "chipotle, cumin and lime"),
            proteins: [Pantry.groundBeef, Pantry.groundTurkey, Pantry.chickenThigh, Pantry.blackBeans, Pantry.shrimp, Pantry.tofu],
            carbs: [Pantry.cornTortillas, Pantry.jasmineRice, Pantry.brownRice, Pantry.sweetPotato, Pantry.cauliflowerRice],
            vegetables: [Pantry.cabbage, Pantry.redOnion, Pantry.bellPepper, Pantry.corn, Pantry.cherryTomatoes, Pantry.romaine],
            minutes: 30, servings: 3
        ),
        MealBlueprint(
            key: "burritobowl",
            cuisine: .mexican, course: .lunch, method: .bowl,
            seasoning: SeasoningProfile(name: "Cilantro-Lime", extras: [Pantry.oliveOil, Pantry.lime, Pantry.avocado, Pantry.salsa], sauceNote: "lime, cilantro and a spoon of salsa"),
            proteins: [Pantry.chickenBreast, Pantry.groundBeef, Pantry.blackBeans, Pantry.tofu, Pantry.sirloin, Pantry.shrimp],
            carbs: [Pantry.brownRice, Pantry.jasmineRice, Pantry.quinoa, Pantry.sweetPotato, Pantry.cauliflowerRice],
            vegetables: [Pantry.bellPepper, Pantry.corn, Pantry.romaine, Pantry.redOnion, Pantry.cherryTomatoes, Pantry.cabbage],
            minutes: 25, servings: 2
        ),

        // ---- Italian ----
        MealBlueprint(
            key: "tomatopasta",
            cuisine: .italian, course: .dinner, method: .pasta,
            seasoning: SeasoningProfile(name: "Tomato-Basil", extras: [Pantry.oliveOil, Pantry.passata, Pantry.parmesan, Pantry.herbs], sauceNote: "garlic, passata and torn basil"),
            proteins: [Pantry.chickenBreast, Pantry.groundTurkey, Pantry.shrimp, Pantry.whiteBeans, Pantry.cannedTuna, Pantry.groundBeef],
            carbs: [Pantry.wholeWheatPasta, Pantry.chickpeaPasta, Pantry.polenta, Pantry.farro, Pantry.barley],
            vegetables: [Pantry.zucchini, Pantry.spinach, Pantry.mushrooms, Pantry.cherryTomatoes, Pantry.eggplant, Pantry.bellPepper],
            minutes: 30, servings: 3
        ),
        MealBlueprint(
            key: "pesto",
            cuisine: .italian, course: .dinner, method: .skillet,
            seasoning: SeasoningProfile(name: "Pesto", extras: [Pantry.pesto, Pantry.oliveOil, Pantry.lemon], sauceNote: "basil pesto loosened with lemon"),
            proteins: [Pantry.chickenBreast, Pantry.salmon, Pantry.shrimp, Pantry.whiteBeans, Pantry.tofu, Pantry.cod],
            carbs: [Pantry.wholeWheatPasta, Pantry.chickpeaPasta, Pantry.quinoa, Pantry.babyPotato, Pantry.farro],
            vegetables: [Pantry.greenBeans, Pantry.cherryTomatoes, Pantry.zucchini, Pantry.asparagus, Pantry.spinach, Pantry.broccoli],
            minutes: 25, servings: 2
        ),
        MealBlueprint(
            key: "ragu",
            cuisine: .italian, course: .dinner, method: .bake,
            seasoning: SeasoningProfile(name: "Slow Ragù", extras: [Pantry.oliveOil, Pantry.passata, Pantry.parmesan], sauceNote: "soffritto, tomato and a long simmer"),
            proteins: [Pantry.groundBeef, Pantry.groundTurkey, Pantry.lentils, Pantry.groundChicken, Pantry.whiteBeans, Pantry.groundLamb],
            carbs: [Pantry.wholeWheatPasta, Pantry.chickpeaPasta, Pantry.polenta, Pantry.babyPotato, Pantry.barley],
            vegetables: [Pantry.carrots, Pantry.mushrooms, Pantry.eggplant, Pantry.zucchini, Pantry.spinach, Pantry.redOnion],
            minutes: 70, servings: 4
        ),
        MealBlueprint(
            key: "frittata",
            cuisine: .italian, course: .breakfast, method: .frittata,
            seasoning: SeasoningProfile(name: "Herb", extras: [Pantry.oliveOil, Pantry.parmesan, Pantry.herbs], sauceNote: "parsley, chives and black pepper"),
            proteins: [Pantry.eggs, Pantry.eggWhites, Pantry.cottageCheese, Pantry.tofu, Pantry.groundTurkey, Pantry.whiteBeans],
            carbs: [Pantry.babyPotato, Pantry.sweetPotato, Pantry.quinoa, Pantry.polenta, Pantry.sourdough],
            vegetables: [Pantry.spinach, Pantry.mushrooms, Pantry.zucchini, Pantry.cherryTomatoes, Pantry.kale, Pantry.bellPepper],
            minutes: 30, servings: 3
        ),

        // ---- Mediterranean / Greek ----
        MealBlueprint(
            key: "medbowl",
            cuisine: .mediterranean, course: .lunch, method: .bowl,
            seasoning: SeasoningProfile(name: "Lemon-Tahini", extras: [Pantry.tahini, Pantry.lemon, Pantry.oliveOil], sauceNote: "tahini thinned with lemon and cold water"),
            proteins: [Pantry.chickenBreast, Pantry.chickpeas, Pantry.salmon, Pantry.halloumi, Pantry.lentils, Pantry.shrimp],
            carbs: [Pantry.quinoa, Pantry.farro, Pantry.couscous, Pantry.barley, Pantry.brownRice],
            vegetables: [Pantry.cherryTomatoes, Pantry.cucumber, Pantry.bellPepper, Pantry.kale, Pantry.redOnion, Pantry.eggplant],
            minutes: 25, servings: 2
        ),
        MealBlueprint(
            key: "lemonherb",
            cuisine: .mediterranean, course: .dinner, method: .skillet,
            seasoning: SeasoningProfile(name: "Lemon-Caper", extras: [Pantry.oliveOil, Pantry.lemon, Pantry.butter, Pantry.herbs], sauceNote: "lemon, capers and a knob of butter"),
            proteins: [Pantry.chickenBreast, Pantry.cod, Pantry.shrimp, Pantry.porkTenderloin, Pantry.tofu, Pantry.scallops],
            carbs: [Pantry.couscous, Pantry.wholeWheatPasta, Pantry.babyPotato, Pantry.farro, Pantry.polenta],
            vegetables: [Pantry.asparagus, Pantry.spinach, Pantry.zucchini, Pantry.greenBeans, Pantry.cherryTomatoes, Pantry.broccoli],
            minutes: 25, servings: 2
        ),
        MealBlueprint(
            key: "greeksalad",
            cuisine: .greek, course: .lunch, method: .salad,
            seasoning: SeasoningProfile(name: "Oregano-Feta", extras: [Pantry.feta, Pantry.oliveOil, Pantry.lemon], sauceNote: "red wine vinegar, oregano and olive oil"),
            proteins: [Pantry.chickenBreast, Pantry.chickpeas, Pantry.shrimp, Pantry.halloumi, Pantry.cannedTuna, Pantry.salmon],
            carbs: [Pantry.quinoa, Pantry.farro, Pantry.pita, Pantry.barley, Pantry.couscous],
            vegetables: [Pantry.cherryTomatoes, Pantry.cucumber, Pantry.redOnion, Pantry.bellPepper, Pantry.romaine, Pantry.kale],
            minutes: 20, servings: 2
        ),

        // ---- Middle Eastern ----
        MealBlueprint(
            key: "harissa",
            cuisine: .middleEastern, course: .dinner, method: .sheetPan,
            seasoning: SeasoningProfile(name: "Harissa", extras: [Pantry.harissa, Pantry.oliveOil, Pantry.lemon], sauceNote: "harissa loosened with olive oil and lemon"),
            proteins: [Pantry.chickenThigh, Pantry.chickpeas, Pantry.lamb, Pantry.cod, Pantry.tofu, Pantry.turkeyBreast],
            carbs: [Pantry.couscous, Pantry.quinoa, Pantry.sweetPotato, Pantry.babyPotato, Pantry.farro],
            vegetables: [Pantry.cauliflower, Pantry.carrots, Pantry.eggplant, Pantry.bellPepper, Pantry.butternut, Pantry.redOnion],
            minutes: 40, servings: 3
        ),
        MealBlueprint(
            key: "shawarma",
            cuisine: .middleEastern, course: .lunch, method: .wrap,
            seasoning: SeasoningProfile(name: "Shawarma-Spiced", extras: [Pantry.spiceBlend, Pantry.oliveOil, Pantry.greekYogurt, Pantry.lemon], sauceNote: "cumin, coriander and garlic yogurt"),
            proteins: [Pantry.chickenBreast, Pantry.lamb, Pantry.chickpeas, Pantry.turkeyBreast, Pantry.tofu, Pantry.halloumi],
            carbs: [Pantry.pita, Pantry.couscous, Pantry.quinoa, Pantry.brownRice, Pantry.cornTortillas],
            vegetables: [Pantry.cabbage, Pantry.cherryTomatoes, Pantry.redOnion, Pantry.romaine, Pantry.bellPepper, Pantry.cucumber],
            minutes: 30, servings: 2
        ),
        MealBlueprint(
            key: "kebab",
            cuisine: .middleEastern, course: .dinner, method: .skewers,
            seasoning: SeasoningProfile(name: "Sumac", extras: [Pantry.spiceBlend, Pantry.oliveOil, Pantry.lemon, Pantry.greekYogurt], sauceNote: "sumac, garlic and yogurt"),
            proteins: [Pantry.chickenBreast, Pantry.lamb, Pantry.sirloin, Pantry.halloumi, Pantry.shrimp, Pantry.tofu],
            carbs: [Pantry.couscous, Pantry.pita, Pantry.quinoa, Pantry.jasmineRice, Pantry.farro],
            vegetables: [Pantry.bellPepper, Pantry.redOnion, Pantry.zucchini, Pantry.eggplant, Pantry.cherryTomatoes, Pantry.mushrooms],
            minutes: 35, servings: 3
        ),

        // ---- Indian ----
        MealBlueprint(
            key: "masala",
            cuisine: .indian, course: .dinner, method: .curry,
            seasoning: SeasoningProfile(name: "Tikka Masala", extras: [Pantry.curryPaste, Pantry.passata, Pantry.oliveOil, Pantry.greekYogurt], sauceNote: "garam masala, ginger and tomato"),
            proteins: [Pantry.chickenBreast, Pantry.paneer, Pantry.chickpeas, Pantry.lamb, Pantry.tofu, Pantry.lentils],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.quinoa, Pantry.cauliflowerRice, Pantry.pita],
            vegetables: [Pantry.spinach, Pantry.cauliflower, Pantry.bellPepper, Pantry.greenBeans, Pantry.butternut, Pantry.carrots],
            minutes: 40, servings: 3
        ),
        MealBlueprint(
            key: "tandoori",
            cuisine: .indian, course: .dinner, method: .bake,
            seasoning: SeasoningProfile(name: "Tandoori", extras: [Pantry.greekYogurt, Pantry.spiceBlend, Pantry.lemon, Pantry.oliveOil], sauceNote: "yogurt, chili and warm spices"),
            proteins: [Pantry.chickenThigh, Pantry.paneer, Pantry.cod, Pantry.chickpeas, Pantry.tofu, Pantry.shrimp],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.quinoa, Pantry.cauliflowerRice, Pantry.pita],
            vegetables: [Pantry.cauliflower, Pantry.bellPepper, Pantry.redOnion, Pantry.spinach, Pantry.carrots, Pantry.broccoli],
            minutes: 45, servings: 3
        ),
        MealBlueprint(
            key: "dal",
            cuisine: .indian, course: .lunch, method: .curry,
            seasoning: SeasoningProfile(name: "Tempered Dal", extras: [Pantry.spiceBlend, Pantry.oliveOil, Pantry.garlicGinger], sauceNote: "cumin seed, turmeric and ginger bloomed in hot oil"),
            proteins: [Pantry.lentils, Pantry.chickpeas, Pantry.tofu, Pantry.paneer, Pantry.whiteBeans, Pantry.eggs],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.quinoa, Pantry.barley, Pantry.pita],
            vegetables: [Pantry.spinach, Pantry.carrots, Pantry.cauliflower, Pantry.kale, Pantry.butternut, Pantry.zucchini],
            minutes: 35, servings: 4
        ),

        // ---- Thai ----
        MealBlueprint(
            key: "thaicurry",
            cuisine: .thai, course: .dinner, method: .curry,
            seasoning: SeasoningProfile(name: "Green Coconut", extras: [Pantry.curryPaste, Pantry.coconutMilk, Pantry.lime], sauceNote: "green curry paste and coconut milk"),
            proteins: [Pantry.chickenThigh, Pantry.shrimp, Pantry.tofu, Pantry.chickpeas, Pantry.cod, Pantry.sirloin],
            carbs: [Pantry.jasmineRice, Pantry.riceNoodles, Pantry.brownRice, Pantry.cauliflowerRice, Pantry.quinoa],
            vegetables: [Pantry.bellPepper, Pantry.snapPeas, Pantry.bokChoy, Pantry.greenBeans, Pantry.eggplant, Pantry.broccoli],
            minutes: 30, servings: 3
        ),
        MealBlueprint(
            key: "larb",
            cuisine: .thai, course: .lunch, method: .salad,
            seasoning: SeasoningProfile(name: "Larb-Style", extras: [Pantry.lime, Pantry.herbs, Pantry.sesameOil], sauceNote: "lime, fish sauce and toasted rice powder"),
            proteins: [Pantry.groundChicken, Pantry.groundTurkey, Pantry.tofu, Pantry.shrimp, Pantry.tempeh, Pantry.groundBeef],
            carbs: [Pantry.jasmineRice, Pantry.riceNoodles, Pantry.cauliflowerRice, Pantry.brownRice, Pantry.quinoa],
            vegetables: [Pantry.cabbage, Pantry.romaine, Pantry.carrots, Pantry.cucumber, Pantry.redOnion, Pantry.snapPeas],
            minutes: 20, servings: 2
        ),
        MealBlueprint(
            key: "peanutnoodle",
            cuisine: .thai, course: .dinner, method: .noodleBowl,
            seasoning: SeasoningProfile(name: "Peanut", extras: [Pantry.peanutButter, Pantry.soySauce, Pantry.lime, Pantry.garlicGinger], sauceNote: "peanut butter, soy, lime and ginger"),
            proteins: [Pantry.chickenBreast, Pantry.tofu, Pantry.shrimp, Pantry.edamame, Pantry.tempeh, Pantry.sirloin],
            carbs: [Pantry.riceNoodles, Pantry.soba, Pantry.wholeWheatPasta, Pantry.jasmineRice, Pantry.brownRice],
            vegetables: [Pantry.carrots, Pantry.cabbage, Pantry.snapPeas, Pantry.bellPepper, Pantry.bokChoy, Pantry.broccoli],
            minutes: 25, servings: 2
        ),

        // ---- Japanese ----
        MealBlueprint(
            key: "teriyaki",
            cuisine: .japanese, course: .dinner, method: .bowl,
            seasoning: SeasoningProfile(name: "Teriyaki", extras: [Pantry.soySauce, Pantry.honey, Pantry.garlicGinger, Pantry.sesameSeeds], sauceNote: "soy, mirin, ginger and a little honey"),
            proteins: [Pantry.salmon, Pantry.chickenThigh, Pantry.tofu, Pantry.sirloin, Pantry.shrimp, Pantry.tempeh],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.soba, Pantry.quinoa, Pantry.cauliflowerRice],
            vegetables: [Pantry.broccoli, Pantry.bokChoy, Pantry.snapPeas, Pantry.carrots, Pantry.spinach, Pantry.mushrooms],
            minutes: 30, servings: 2
        ),
        MealBlueprint(
            key: "miso",
            cuisine: .japanese, course: .dinner, method: .bake,
            seasoning: SeasoningProfile(name: "Miso-Glazed", extras: [Pantry.miso, Pantry.honey, Pantry.sesameOil, Pantry.sesameSeeds], sauceNote: "white miso whisked with mirin and honey"),
            proteins: [Pantry.salmon, Pantry.cod, Pantry.tofu, Pantry.chickenBreast, Pantry.tempeh, Pantry.scallops],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.soba, Pantry.barley, Pantry.quinoa],
            vegetables: [Pantry.bokChoy, Pantry.broccoli, Pantry.asparagus, Pantry.mushrooms, Pantry.eggplant, Pantry.snapPeas],
            minutes: 30, servings: 2
        ),
        MealBlueprint(
            key: "poke",
            cuisine: .japanese, course: .lunch, method: .poke,
            seasoning: SeasoningProfile(name: "Shoyu", extras: [Pantry.soySauce, Pantry.sesameOil, Pantry.avocado, Pantry.sesameSeeds], sauceNote: "soy, sesame oil and rice vinegar"),
            proteins: [Pantry.salmon, Pantry.cannedTuna, Pantry.tofu, Pantry.shrimp, Pantry.edamame, Pantry.scallops],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.quinoa, Pantry.soba, Pantry.cauliflowerRice],
            vegetables: [Pantry.cucumber, Pantry.carrots, Pantry.cabbage, Pantry.spinach, Pantry.snapPeas, Pantry.redOnion],
            minutes: 20, servings: 2
        ),

        // ---- Korean ----
        MealBlueprint(
            key: "bibimbap",
            cuisine: .korean, course: .dinner, method: .bowl,
            seasoning: SeasoningProfile(name: "Gochujang", extras: [Pantry.gochujang, Pantry.sesameOil, Pantry.sesameSeeds, Pantry.garlicGinger], sauceNote: "gochujang, sesame oil and rice vinegar"),
            proteins: [Pantry.groundBeef, Pantry.chickenBreast, Pantry.tofu, Pantry.tempeh, Pantry.eggs, Pantry.shrimp],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.soba, Pantry.quinoa, Pantry.barley],
            vegetables: [Pantry.spinach, Pantry.carrots, Pantry.mushrooms, Pantry.cabbage, Pantry.bokChoy, Pantry.snapPeas],
            minutes: 35, servings: 2
        ),

        // ---- Chinese ----
        MealBlueprint(
            key: "stirfry",
            cuisine: .chinese, course: .dinner, method: .stirFry,
            seasoning: SeasoningProfile(name: "Garlic-Ginger", extras: [Pantry.soySauce, Pantry.garlicGinger, Pantry.sesameOil], sauceNote: "soy, ginger, garlic and a splash of stock"),
            proteins: [Pantry.chickenBreast, Pantry.sirloin, Pantry.shrimp, Pantry.tofu, Pantry.tempeh, Pantry.groundChicken],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.riceNoodles, Pantry.soba, Pantry.cauliflowerRice],
            vegetables: [Pantry.broccoli, Pantry.snapPeas, Pantry.bokChoy, Pantry.bellPepper, Pantry.mushrooms, Pantry.cabbage],
            minutes: 20, servings: 2
        ),
        MealBlueprint(
            key: "sesamecrunch",
            cuisine: .chinese, course: .lunch, method: .salad,
            seasoning: SeasoningProfile(name: "Sesame-Crunch", extras: [Pantry.sesameOil, Pantry.soySauce, Pantry.cashews, Pantry.sesameSeeds], sauceNote: "sesame oil, rice vinegar and a little soy"),
            proteins: [Pantry.chickenBreast, Pantry.tofu, Pantry.edamame, Pantry.shrimp, Pantry.tempeh, Pantry.turkeyBreast],
            carbs: [Pantry.soba, Pantry.riceNoodles, Pantry.quinoa, Pantry.brownRice, Pantry.jasmineRice],
            vegetables: [Pantry.cabbage, Pantry.carrots, Pantry.snapPeas, Pantry.bellPepper, Pantry.cucumber, Pantry.bokChoy],
            minutes: 20, servings: 2
        ),
        MealBlueprint(
            key: "congee",
            cuisine: .chinese, course: .breakfast, method: .congee,
            seasoning: SeasoningProfile(name: "Ginger-Scallion", extras: [Pantry.garlicGinger, Pantry.soySauce, Pantry.sesameOil, Pantry.chiliCrisp], sauceNote: "ginger, scallion, soy and chili crisp"),
            proteins: [Pantry.eggs, Pantry.chickenBreast, Pantry.tofu, Pantry.shrimp, Pantry.groundChicken, Pantry.edamame],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.barley, Pantry.oatmeal, Pantry.quinoa],
            vegetables: [Pantry.bokChoy, Pantry.spinach, Pantry.mushrooms, Pantry.cabbage, Pantry.carrots, Pantry.snapPeas],
            minutes: 45, servings: 2
        ),

        // ---- Vietnamese ----
        MealBlueprint(
            key: "pho",
            cuisine: .vietnamese, course: .dinner, method: .noodleBowl,
            seasoning: SeasoningProfile(name: "Star-Anise Broth", extras: [Pantry.garlicGinger, Pantry.herbs, Pantry.lime, Pantry.soySauce], sauceNote: "charred ginger, star anise and cinnamon"),
            proteins: [Pantry.sirloin, Pantry.chickenBreast, Pantry.tofu, Pantry.shrimp, Pantry.groundChicken, Pantry.tempeh],
            carbs: [Pantry.riceNoodles, Pantry.soba, Pantry.jasmineRice, Pantry.brownRice, Pantry.cauliflowerRice],
            vegetables: [Pantry.bokChoy, Pantry.cabbage, Pantry.carrots, Pantry.snapPeas, Pantry.mushrooms, Pantry.spinach],
            minutes: 40, servings: 2
        ),
        MealBlueprint(
            key: "banhmi",
            cuisine: .vietnamese, course: .lunch, method: .bowl,
            seasoning: SeasoningProfile(name: "Lemongrass", extras: [Pantry.lime, Pantry.soySauce, Pantry.herbs, Pantry.honey], sauceNote: "lemongrass, lime and a touch of honey"),
            proteins: [Pantry.porkTenderloin, Pantry.chickenThigh, Pantry.tofu, Pantry.tempeh, Pantry.shrimp, Pantry.groundChicken],
            carbs: [Pantry.jasmineRice, Pantry.riceNoodles, Pantry.brownRice, Pantry.quinoa, Pantry.pita],
            vegetables: [Pantry.carrots, Pantry.cucumber, Pantry.cabbage, Pantry.redOnion, Pantry.romaine, Pantry.bellPepper],
            minutes: 30, servings: 2
        ),

        // ---- Caribbean / Spanish / French ----
        MealBlueprint(
            key: "jerk",
            cuisine: .caribbean, course: .dinner, method: .grill,
            seasoning: SeasoningProfile(name: "Jerk-Spiced", extras: [Pantry.spiceBlend, Pantry.oliveOil, Pantry.lime, Pantry.honey], sauceNote: "allspice, thyme, scotch bonnet and lime"),
            proteins: [Pantry.chickenThigh, Pantry.chickenBreast, Pantry.salmon, Pantry.tofu, Pantry.porkTenderloin, Pantry.shrimp],
            carbs: [Pantry.brownRice, Pantry.jasmineRice, Pantry.sweetPotato, Pantry.barley, Pantry.quinoa],
            vegetables: [Pantry.bellPepper, Pantry.cabbage, Pantry.corn, Pantry.redOnion, Pantry.carrots, Pantry.butternut],
            minutes: 35, servings: 3
        ),
        MealBlueprint(
            key: "paella",
            cuisine: .spanish, course: .dinner, method: .skillet,
            seasoning: SeasoningProfile(name: "Saffron", extras: [Pantry.oliveOil, Pantry.passata, Pantry.spiceBlend, Pantry.lemon], sauceNote: "saffron, smoked paprika and sofrito"),
            proteins: [Pantry.shrimp, Pantry.chickenThigh, Pantry.mussels, Pantry.chickpeas, Pantry.cod, Pantry.scallops],
            carbs: [Pantry.jasmineRice, Pantry.brownRice, Pantry.quinoa, Pantry.barley, Pantry.farro],
            vegetables: [Pantry.bellPepper, Pantry.greenBeans, Pantry.cherryTomatoes, Pantry.redOnion, Pantry.snapPeas, Pantry.asparagus],
            minutes: 45, servings: 4
        ),
        MealBlueprint(
            key: "frenchbraise",
            cuisine: .french, course: .dinner, method: .braise,
            seasoning: SeasoningProfile(name: "Herbes-de-Provence", extras: [Pantry.oliveOil, Pantry.herbs, Pantry.butter, Pantry.passata], sauceNote: "thyme, rosemary and stock reduced with a little butter"),
            proteins: [Pantry.chickenThigh, Pantry.porkTenderloin, Pantry.whiteBeans, Pantry.sirloin, Pantry.lentils, Pantry.turkeyBreast],
            carbs: [Pantry.babyPotato, Pantry.polenta, Pantry.farro, Pantry.barley, Pantry.brownRice],
            vegetables: [Pantry.carrots, Pantry.mushrooms, Pantry.greenBeans, Pantry.butternut, Pantry.kale, Pantry.redOnion],
            minutes: 75, servings: 4
        ),
    ]
}
