import Foundation

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
