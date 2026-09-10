import SwiftUI
import ForgeCore

/// First open of Lifestyle — not onboarding. Tutorial, then who-you-are questions
/// that shift QoL weights. ARIA uses the same persona Life just saved.
struct LifestyleInterviewOverlay: View {
    var onFinished: () -> Void

    @State private var step = 0
    @State private var archetype: QualityOfLifeArchetype = .balanced
    @State private var sleepNeed: Double = 8
    @State private var socialEnergy: Double = 6
    @State private var workStrain: Double = 4
    @State private var nutrition = "fuel"

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
                    Button(step >= 6 ? "That's me" : "Continue") { advance() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.ember)
                        .clipShape(Capsule())
                }
            }
            .padding(22)
            .background(Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(20)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            copy(
                title: "This is Lifestyle.",
                body: "Nutrition, movement, sleep, and how the week actually felt. Not a second Home — the room where we grade quality of life."
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
            sliderBlock(
                title: "How much sleep do you actually want?",
                value: $sleepNeed,
                range: 5...9,
                label: String(format: "%.1f hours", sleepNeed)
            )
        case 4:
            sliderBlock(
                title: "Social energy this season",
                value: $socialEnergy,
                range: 0...10,
                label: String(format: "%.0f / 10", socialEnergy)
            )
        case 5:
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

    private func advance() {
        if step < 6 {
            step += 1
            return
        }
        let persona = QualityOfLifePersona(
            archetype: archetype,
            sleepNeedPreferenceHours: sleepNeed,
            socialEnergy0to10: socialEnergy,
            workStrain0to10: workStrain,
            nutritionRelationship: nutrition
        )
        QualityOfLifeLivingStore.savePersona(persona)
        QualityOfLifeLivingStore.markInterviewCompleted()
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
            category: .inferences,
            kind: "qol_weights",
            summary: inferenceLine(persona),
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
