import Foundation

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
