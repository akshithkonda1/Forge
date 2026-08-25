import SwiftUI
import Combine
import ForgeCore

let popularRestaurants: [Restaurant] = [
    Restaurant(name: "Raising Cane's", logo: "🍗", items: [
        MenuItem(name: "Box Combo (4 tenders)",    calories: 1220, protein: 56, carbs: 120, fat: 55, serving: "1 combo",   isHealthy: false),
        MenuItem(name: "Chicken Finger (1 piece)", calories: 130,  protein: 10, carbs: 8,   fat: 6,  serving: "1 tender",  isHealthy: true),
        MenuItem(name: "Crinkle Fries",            calories: 390,  protein: 5,  carbs: 50,  fat: 18, serving: "1 order",   isHealthy: false),
        MenuItem(name: "Coleslaw",                 calories: 170,  protein: 2,  carbs: 14,  fat: 13, serving: "1 order",   isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "McDonald's", logo: "🍔", items: [
        MenuItem(name: "Egg McMuffin",             calories: 310, protein: 17, carbs: 30, fat: 13, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Grilled Chicken Sandwich", calories: 380, protein: 37, carbs: 44, fat: 7,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Big Mac",                  calories: 550, protein: 25, carbs: 45, fat: 30, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "Medium Fries",             calories: 320, protein: 4,  carbs: 43, fat: 15, serving: "1 order",    isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Chick-fil-A", logo: "🐔", items: [
        MenuItem(name: "Grilled Nuggets (8-count)",    calories: 130, protein: 25, carbs: 1,  fat: 3,  serving: "8 pieces",  isHealthy: true),
        MenuItem(name: "Grilled Chicken Sandwich",     calories: 320, protein: 30, carbs: 42, fat: 6,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Cobb Salad (Grilled)",         calories: 390, protein: 40, carbs: 28, fat: 14, serving: "1 salad",    isHealthy: true),
        MenuItem(name: "Chicken Sandwich (fried)",     calories: 440, protein: 28, carbs: 41, fat: 19, serving: "1 sandwich", isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "Chipotle", logo: "🌯", items: [
        MenuItem(name: "Chicken Bowl (no rice)",  calories: 320,  protein: 42, carbs: 21,  fat: 8,  serving: "1 bowl",    isHealthy: true),
        MenuItem(name: "Chicken Salad",           calories: 500,  protein: 44, carbs: 36,  fat: 21, serving: "1 salad",   isHealthy: true),
        MenuItem(name: "Chicken Burrito",         calories: 1025, protein: 65, carbs: 123, fat: 30, serving: "1 burrito", isHealthy: false),
        MenuItem(name: "Veggie Bowl",             calories: 430,  protein: 16, carbs: 68,  fat: 12, serving: "1 bowl",    isHealthy: true),
    ], category: .mexican),

    Restaurant(name: "Subway", logo: "🥖", items: [
        MenuItem(name: "6\" Turkey Breast",  calories: 280, protein: 18, carbs: 46, fat: 4,  serving: "6 inch", isHealthy: true),
        MenuItem(name: "Grilled Chicken Salad", calories: 130, protein: 19, carbs: 10, fat: 3, serving: "1 salad", isHealthy: true),
        MenuItem(name: "6\" Veggie Delite",  calories: 230, protein: 9,  carbs: 44, fat: 3,  serving: "6 inch", isHealthy: true),
        MenuItem(name: "6\" Spicy Italian",  calories: 480, protein: 21, carbs: 46, fat: 24, serving: "6 inch", isHealthy: false),
    ], category: .healthy),

    Restaurant(name: "Panera Bread", logo: "🥗", items: [
        MenuItem(name: "Green Goddess Cobb Salad", calories: 550, protein: 42, carbs: 23, fat: 33, serving: "1 salad", isHealthy: true),
        MenuItem(name: "Chicken Noodle Soup",      calories: 90,  protein: 7,  carbs: 10, fat: 3,  serving: "1 cup",  isHealthy: true),
        MenuItem(name: "Mediterranean Grain Bowl", calories: 430, protein: 16, carbs: 48, fat: 21, serving: "1 bowl", isHealthy: true),
        MenuItem(name: "Turkey Bravo Sandwich",    calories: 830, protein: 44, carbs: 76, fat: 37, serving: "1 item", isHealthy: false),
    ], category: .healthy),

    Restaurant(name: "Taco Bell", logo: "🌮", items: [
        MenuItem(name: "Chicken Power Bowl",  calories: 470, protein: 26, carbs: 50, fat: 19, serving: "1 bowl",  isHealthy: true),
        MenuItem(name: "Fresco Crunchy Taco", calories: 140, protein: 7,  carbs: 13, fat: 7,  serving: "1 taco",  isHealthy: true),
        MenuItem(name: "Crunchwrap Supreme",  calories: 530, protein: 16, carbs: 71, fat: 21, serving: "1 item",  isHealthy: false),
        MenuItem(name: "Black Beans",         calories: 80,  protein: 5,  carbs: 14, fat: 0,  serving: "1 side",  isHealthy: true),
    ], category: .mexican),

    Restaurant(name: "Wendy's", logo: "🍔", items: [
        MenuItem(name: "Grilled Chicken Sandwich",       calories: 350, protein: 35, carbs: 37, fat: 8,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Southwest Avocado Salad",        calories: 540, protein: 43, carbs: 32, fat: 27, serving: "1 salad",    isHealthy: true),
        MenuItem(name: "Dave's Single",                  calories: 590, protein: 30, carbs: 39, fat: 34, serving: "1 burger",   isHealthy: false),
        MenuItem(name: "10 Piece Chicken Nuggets",       calories: 450, protein: 23, carbs: 31, fat: 27, serving: "10 pieces",  isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Whataburger", logo: "🍔", items: [
        MenuItem(name: "Whataburger (Single)", calories: 590, protein: 29, carbs: 62, fat: 27, serving: "1 burger", isHealthy: false),
        MenuItem(name: "Grilled Chicken Sandwich", calories: 430, protein: 32, carbs: 48, fat: 12, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Apple & Cranberry Chicken Salad", calories: 390, protein: 34, carbs: 28, fat: 14, serving: "1 salad", isHealthy: true),
    ], category: .burgers),

    Restaurant(name: "Sweetgreen", logo: "🥗", items: [
        MenuItem(name: "Harvest Bowl", calories: 685, protein: 31, carbs: 71, fat: 32, serving: "1 bowl", isHealthy: true),
        MenuItem(name: "Kale Caesar", calories: 430, protein: 18, carbs: 24, fat: 30, serving: "1 salad", isHealthy: true),
        MenuItem(name: "Chicken Pesto Parm", calories: 525, protein: 36, carbs: 42, fat: 24, serving: "1 bowl", isHealthy: true),
    ], category: .healthy),

    Restaurant(name: "Wingstop", logo: "🍗", items: [
        MenuItem(name: "Classic Wings (6 pc)", calories: 480, protein: 42, carbs: 8, fat: 32, serving: "6 pieces", isHealthy: false),
        MenuItem(name: "Boneless Wings (8 pc)", calories: 520, protein: 38, carbs: 32, fat: 28, serving: "8 pieces", isHealthy: false),
        MenuItem(name: "Lemon Pepper Wings (6 pc)", calories: 500, protein: 40, carbs: 10, fat: 34, serving: "6 pieces", isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "In-N-Out Burger", logo: "🍔", items: [
        MenuItem(name: "Protein Style Burger", calories: 330, protein: 18, carbs: 11, fat: 25, serving: "1 burger", isHealthy: true),
        MenuItem(name: "Grilled Cheese", calories: 380, protein: 15, carbs: 39, fat: 19, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "Double-Double", calories: 670, protein: 37, carbs: 39, fat: 41, serving: "1 burger", isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Starbucks", logo: "☕️", items: [
        MenuItem(name: "Egg White & Roasted Red Pepper Egg Bites", calories: 170, protein: 12, carbs: 11, fat: 8, serving: "2 bites", isHealthy: true),
        MenuItem(name: "Spinach Feta Wrap", calories: 290, protein: 19, carbs: 34, fat: 10, serving: "1 wrap", isHealthy: true),
        MenuItem(name: "Grande Latte (2% milk)", calories: 190, protein: 12, carbs: 18, fat: 7, serving: "16 oz", isHealthy: true),
    ], category: .healthy),

    Restaurant(name: "Cava", logo: "🥙", items: [
        MenuItem(name: "Grilled Chicken Bowl", calories: 610, protein: 42, carbs: 52, fat: 24, serving: "1 bowl", isHealthy: true),
        MenuItem(name: "Greens + Grains Bowl", calories: 520, protein: 18, carbs: 68, fat: 18, serving: "1 bowl", isHealthy: true),
    ], category: .healthy),

    Restaurant(name: "Shake Shack", logo: "🍔", items: [
        MenuItem(name: "Lettuce Wrap ShackBurger", calories: 320, protein: 25, carbs: 6, fat: 22, serving: "1 burger", isHealthy: true),
        MenuItem(name: "Chicken Shack", calories: 550, protein: 33, carbs: 36, fat: 31, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "ShackBurger (Single)", calories: 530, protein: 28, carbs: 27, fat: 34, serving: "1 burger", isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Burger King", logo: "👑", items: [
        MenuItem(name: "Whopper Jr. (no mayo)", calories: 240, protein: 13, carbs: 27, fat: 9,  serving: "1 burger",   isHealthy: true),
        MenuItem(name: "Grilled Chicken Sandwich", calories: 400, protein: 32, carbs: 43, fat: 11, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Whopper",                calories: 670, protein: 31, carbs: 51, fat: 40, serving: "1 burger",   isHealthy: false),
        MenuItem(name: "8 Pc Chicken Nuggets",   calories: 350, protein: 17, carbs: 19, fat: 22, serving: "8 pieces",   isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Popeyes", logo: "🍗", items: [
        MenuItem(name: "Blackened Chicken Tenders (3)", calories: 170, protein: 27, carbs: 2,  fat: 5,  serving: "3 tenders", isHealthy: true),
        MenuItem(name: "Red Beans & Rice (regular)",    calories: 230, protein: 6,  carbs: 31, fat: 9,  serving: "1 side",    isHealthy: true),
        MenuItem(name: "Chicken Sandwich",              calories: 700, protein: 28, carbs: 50, fat: 42, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "Cajun Fries (regular)",         calories: 260, protein: 4,  carbs: 33, fat: 13, serving: "1 order",   isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "KFC", logo: "🍗", items: [
        MenuItem(name: "Grilled Chicken Breast", calories: 210, protein: 38, carbs: 0,  fat: 7,  serving: "1 piece",   isHealthy: true),
        MenuItem(name: "Green Beans",            calories: 25,  protein: 1,  carbs: 5,  fat: 0,  serving: "1 side",    isHealthy: true),
        MenuItem(name: "Original Recipe Breast", calories: 390, protein: 39, carbs: 11, fat: 21, serving: "1 piece",   isHealthy: false),
        MenuItem(name: "Mac & Cheese",           calories: 170, protein: 6,  carbs: 19, fat: 8,  serving: "1 side",    isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "Domino's", logo: "🍕", items: [
        MenuItem(name: "Thin Crust Chicken & Veg (2 slices)", calories: 340, protein: 20, carbs: 30, fat: 15, serving: "2 slices", isHealthy: true),
        MenuItem(name: "Chicken Caesar Salad",                calories: 220, protein: 22, carbs: 10, fat: 10, serving: "1 salad",  isHealthy: true),
        MenuItem(name: "Hand Tossed Pepperoni (2 slices)",    calories: 420, protein: 18, carbs: 46, fat: 18, serving: "2 slices", isHealthy: false),
        MenuItem(name: "Garlic Bread Twists (2)",             calories: 280, protein: 6,  carbs: 34, fat: 13, serving: "2 pieces", isHealthy: false),
    ], category: .pizza),

    Restaurant(name: "Papa John's", logo: "🍕", items: [
        MenuItem(name: "Thin Crust Grilled Chicken (2 slices)", calories: 360, protein: 20, carbs: 32, fat: 16, serving: "2 slices", isHealthy: true),
        MenuItem(name: "Garden Fresh Original (2 slices)",      calories: 380, protein: 15, carbs: 52, fat: 12, serving: "2 slices", isHealthy: true),
        MenuItem(name: "The Works (2 slices)",                  calories: 460, protein: 20, carbs: 52, fat: 19, serving: "2 slices", isHealthy: false),
    ], category: .pizza),

    Restaurant(name: "Panda Express", logo: "🥡", items: [
        MenuItem(name: "Grilled Teriyaki Chicken", calories: 300, protein: 36, carbs: 8,  fat: 13, serving: "1 entree", isHealthy: true),
        MenuItem(name: "Super Greens",             calories: 90,  protein: 6,  carbs: 10, fat: 3,  serving: "1 side",   isHealthy: true),
        MenuItem(name: "String Bean Chicken Breast", calories: 210, protein: 14, carbs: 13, fat: 12, serving: "1 entree", isHealthy: true),
        MenuItem(name: "Orange Chicken",           calories: 490, protein: 25, carbs: 51, fat: 23, serving: "1 entree", isHealthy: false),
    ], category: .fastFood),

    Restaurant(name: "Jersey Mike's", logo: "🥪", items: [
        MenuItem(name: "Turkey Sub in a Tub",       calories: 240, protein: 25, carbs: 10, fat: 11, serving: "1 tub",   isHealthy: true),
        MenuItem(name: "Roast Beef Mini Sub",       calories: 380, protein: 30, carbs: 44, fat: 8,  serving: "1 mini",  isHealthy: true),
        MenuItem(name: "Original Italian (Regular)", calories: 800, protein: 39, carbs: 68, fat: 41, serving: "1 sub",  isHealthy: false),
    ], category: .fastFood),

    Restaurant(name: "Five Guys", logo: "🍔", items: [
        MenuItem(name: "Little Hamburger (no bun)", calories: 300, protein: 25, carbs: 2,  fat: 22, serving: "1 patty",  isHealthy: true),
        MenuItem(name: "Veggie Sandwich",           calories: 440, protein: 11, carbs: 60, fat: 17, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Bacon Cheeseburger",        calories: 920, protein: 51, carbs: 40, fat: 62, serving: "1 burger", isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Chili's", logo: "🌶️", items: [
        MenuItem(name: "6 oz Sirloin with Broccoli", calories: 340, protein: 41, carbs: 10, fat: 15, serving: "1 plate",  isHealthy: true),
        MenuItem(name: "Grilled Chicken Fajitas",    calories: 480, protein: 52, carbs: 22, fat: 20, serving: "1 order",  isHealthy: true),
        MenuItem(name: "Santa Fe Chicken Salad",     calories: 660, protein: 47, carbs: 26, fat: 42, serving: "1 salad",  isHealthy: false),
    ], category: .fastFood),

    Restaurant(name: "Olive Garden", logo: "🍝", items: [
        MenuItem(name: "Herb-Grilled Salmon",       calories: 460, protein: 46, carbs: 6,  fat: 27, serving: "1 plate",  isHealthy: true),
        MenuItem(name: "Minestrone Soup",           calories: 110, protein: 5,  carbs: 20, fat: 1,  serving: "1 bowl",   isHealthy: true),
        MenuItem(name: "Chicken Alfredo",           calories: 1550, protein: 74, carbs: 98, fat: 97, serving: "1 plate", isHealthy: false),
    ], category: .fastFood),

    Restaurant(name: "Dunkin'", logo: "🍩", items: [
        MenuItem(name: "Wake-Up Wrap (Egg & Cheese)", calories: 180, protein: 10, carbs: 14, fat: 10, serving: "1 wrap",  isHealthy: true),
        MenuItem(name: "Sourdough Breakfast Sandwich", calories: 700, protein: 30, carbs: 51, fat: 41, serving: "1 item", isHealthy: false),
        MenuItem(name: "Glazed Donut",                calories: 240, protein: 4,  carbs: 33, fat: 11, serving: "1 donut", isHealthy: false),
    ], category: .fastFood),

    Restaurant(name: "Jimmy John's", logo: "🥖", items: [
        MenuItem(name: "Turkey Tom Unwich",     calories: 260, protein: 20, carbs: 7,  fat: 17, serving: "1 unwich", isHealthy: true),
        MenuItem(name: "Little John Roast Beef", calories: 350, protein: 20, carbs: 45, fat: 9, serving: "1 mini",   isHealthy: true),
        MenuItem(name: "Italian Night Club",    calories: 900, protein: 41, carbs: 70, fat: 50, serving: "1 sub",    isHealthy: false),
    ], category: .fastFood),

    Restaurant(name: "Qdoba", logo: "🌯", items: [
        MenuItem(name: "Grilled Chicken Protein Bowl", calories: 380, protein: 45, carbs: 20, fat: 14, serving: "1 bowl",  isHealthy: true),
        MenuItem(name: "Fajita Veggie Bowl",           calories: 420, protein: 14, carbs: 62, fat: 13, serving: "1 bowl",  isHealthy: true),
        MenuItem(name: "Loaded Steak Burrito",         calories: 1100, protein: 55, carbs: 118, fat: 44, serving: "1 burrito", isHealthy: false),
    ], category: .mexican),

    Restaurant(name: "Noodles & Company", logo: "🍜", items: [
        MenuItem(name: "Zucchini Pesto with Grilled Chicken", calories: 380, protein: 34, carbs: 16, fat: 22, serving: "1 regular", isHealthy: true),
        MenuItem(name: "Japanese Pan Noodles",                calories: 630, protein: 17, carbs: 96, fat: 19, serving: "1 regular", isHealthy: false),
        MenuItem(name: "Wisconsin Mac & Cheese",              calories: 950, protein: 33, carbs: 100, fat: 46, serving: "1 regular", isHealthy: false),
    ], category: .fastFood),

    Restaurant(name: "Zaxby's", logo: "🍗", items: [
        MenuItem(name: "Grilled Chicken Sandwich",     calories: 400, protein: 33, carbs: 42, fat: 11, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Grilled House Zalad",          calories: 350, protein: 38, carbs: 16, fat: 15, serving: "1 salad",    isHealthy: true),
        MenuItem(name: "Chicken Finger Plate (4)",     calories: 1050, protein: 47, carbs: 89, fat: 55, serving: "1 plate",   isHealthy: false),
    ], category: .chicken),
]
