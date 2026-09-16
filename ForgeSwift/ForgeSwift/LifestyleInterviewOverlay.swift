import SwiftUI
import ForgeCore

/// First open of Lifestyle — not onboarding. Tutorial, then who-you-are questions
/// that shift QoL weights and store a local living character. ARIA uses the same
/// persona Life just saved — on-device, no model trip, no family tree.
struct LifestyleInterviewOverlay: View {
    var onFinished: () -> Void

    private let lastStep = 8

    @State private var step = 0
    @State private var archetype: QualityOfLifeArchetype = .balanced
    @State private var movement: LivingMovementPreference = .mix
    @State private var hobbies: [LivingHobby] = []
    @State private var sleepNeed: Double = 8
    @State private var socialEnergy: Double = 6
    @State private var workStrain: Double = 4
    @State private var nutrition = "fuel"
    @State private var eatingRhythm: LivingEatingRhythm = .moderate

    private let nutritionChoices = ["fuel", "comfort", "chaotic", "careful"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("ARIA")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.ember)
                    .tracking(1.2)
                content
                HStack {
                    if step > 0 {
                        Button("Back") { step -= 1 }
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button(step >= lastStep ? "That's me" : "Continue") { advance() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.ember)
                        .clipShape(Capsule())
                }
            }
            .padding(22)
            .forgeGlassCard(cornerRadius: 22, accent: .ember)
            .padding(20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            copy(
                title: "This is Lifestyle.",
                body: "How you live a normal week — food, movement, sleep, free days. Not a second Home, and not an interrogation. I store that character locally so I can decide fast without calling the model."
            )
        case 1:
            copy(
                title: "How I grade QoL.",
                body: "I am not chasing a generic 8 hours and 10k steps. I am asking: are you happy, unstressed, mentally here, and still healthy in the life you actually live? 100 is possible. It is not the point. Life and I use the same number."
            )
        case 2:
            VStack(alignment: .leading, spacing: 12) {
                Text("Who are you, on a normal week?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                choice("Homebody", selected: archetype == .homebody) { archetype = .homebody }
                choice("Outdoors / camping weekends", selected: archetype == .outdoors) { archetype = .outdoors }
                choice("A mix", selected: archetype == .balanced) { archetype = .balanced }
            }
        case 3:
            VStack(alignment: .leading, spacing: 12) {
                Text("How do you like to move?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Not a program. The shape of a typical week.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                ForEach(LivingMovementPreference.allCases, id: \.self) { item in
                    choice(item.title, selected: movement == item) { movement = item }
                }
            }
        case 4:
            VStack(alignment: .leading, spacing: 12) {
                Text("What fills a free day?")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("Pick up to three. Hobbies, not relatives.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                ForEach(LivingHobby.allCases, id: \.self) { item in
                    choice(item.title, selected: hobbies.contains(item)) {
                        toggleHobby(item)
                    }
                }
            }
        case 5:
            sliderBlock(
                title: "How much sleep do you actually want?",
                value: $sleepNeed,
                range: 5...9,
                label: String(format: "%.1f hours", sleepNeed)
            )
        case 6:
            sliderBlock(
                title: "Social energy this season",
                value: $socialEnergy,
                range: 0...10,
                label: String(format: "%.0f / 10", socialEnergy)
            )
        case 7:
            sliderBlock(
                title: "Work / money strain — not salary, just how heavy it feels",
                value: $workStrain,
                range: 0...10,
                label: String(format: "%.0f / 10", workStrain)
            )
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text("Food, for you, is mostly…")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.textPrimary)
                ForEach(nutritionChoices, id: \.self) { item in
                    choice(item.capitalized, selected: nutrition == item) { nutrition = item }
                }
                Text("And a normal day of eating is…")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
                    .padding(.top, 8)
                ForEach(LivingEatingRhythm.allCases, id: \.self) { item in
                    choice(item.title, selected: eatingRhythm == item) { eatingRhythm = item }
                }
            }
        }
    }

    private func copy(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Text(body)
                .font(.system(size: 15))
                .foregroundColor(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .foregroundColor(.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.ember)
                }
            }
            .padding(12)
            .background(selected ? Color.ember.opacity(0.12) : Color.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sliderBlock(title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)
            Slider(value: value, in: range, step: 0.5)
                .tint(.ember)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.ember)
        }
    }

    private func toggleHobby(_ item: LivingHobby) {
        if let idx = hobbies.firstIndex(of: item) {
            hobbies.remove(at: idx)
            return
        }
        guard hobbies.count < 3 else { return }
        hobbies.append(item)
    }

    private func advance() {
        if step < lastStep {
            step += 1
            return
        }
        let persona = QualityOfLifePersona(
            archetype: archetype,
            sleepNeedPreferenceHours: sleepNeed,
            socialEnergy0to10: socialEnergy,
            workStrain0to10: workStrain,
            nutritionRelationship: nutrition,
            eatingRhythm: eatingRhythm,
            movementPreference: movement,
            hobbies: hobbies.isEmpty ? nil : hobbies
        )
        QualityOfLifeLivingStore.savePersona(persona)
        QualityOfLifeLivingStore.markInterviewCompleted()
        AriaContextStore.shared.applyLivingCharacterTags(persona.livingTags())
        let source = "lifestyle-interview"
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "lifestyle_archetype",
            summary: "You said you're a \(persona.archetype.title.lowercased()).",
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "sleep_need",
            summary: String(format: "You want about %.1f hours of sleep.", sleepNeed),
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "living_movement",
            summary: "You typically like to \(movement.title.lowercased()).",
            source: source
        ))
        if !hobbies.isEmpty {
            AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
                category: .weSpokeAbout,
                kind: "living_hobbies",
                summary: "Free days: \(hobbies.map(\.title.lowercased()).joined(separator: ", ")).",
                source: source
            ))
        }
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .weSpokeAbout,
            kind: "living_eating",
            summary: "Food is \(nutrition), \(eatingRhythm.title.lowercased()).",
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .inferences,
            kind: "qol_weights",
            summary: inferenceLine(persona),
            source: source
        ))
        AriaKnowledgeLedgerStore.file(AriaKnowledgeFact(
            category: .inferences,
            kind: "living_character",
            summary: "Local character stored so ARIA can decide without a model round-trip.",
            source: source
        ))
        onFinished()
    }

    private func inferenceLine(_ persona: QualityOfLifePersona) -> String {
        switch persona.archetype {
        case .homebody:
            return "QoL weights sleep and nutrition over activity because you live more at home."
        case .outdoors:
            return "QoL weights activity, then vitals, nutrition, then sleep — weekends outside count."
        case .balanced, .unset:
            return "QoL stays balanced across sleep, movement, food, mind, and connection."
        }
    }
}
