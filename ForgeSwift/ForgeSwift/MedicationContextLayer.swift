import Foundation

/// Every body-system / care-domain archetype the pharmacy and ARIA reason over.
/// ICD-chapter care plus therapeutic classes — not a diagnosis, a filing system.
enum MedicationArchetype: String, CaseIterable, Identifiable, Sendable {
    case cardiovascular = "Cardiovascular"
    case metabolic = "Metabolic"
    case endocrine = "Endocrine"
    case neurology = "Neurology"
    case psychiatry = "Psychiatry"
    case infectious = "Infectious disease"
    case oncology = "Oncology"
    case immunology = "Immunology"
    case respiratory = "Respiratory"
    case gastroenterology = "Gastroenterology"
    case hepatology = "Hepatology"
    case nephrology = "Nephrology"
    case hematology = "Hematology"
    case rheumatology = "Rheumatology"
    case dermatology = "Dermatology"
    case ophthalmology = "Ophthalmology"
    case otolaryngology = "Otolaryngology"
    case urology = "Urology"
    case womensHealth = "Women's health"
    case mensHealth = "Men's health"
    case obstetrics = "Obstetrics"
    case pediatrics = "Pediatrics"
    case pain = "Pain"
    case sleepMedicine = "Sleep medicine"
    case allergy = "Allergy"
    case vaccine = "Vaccine"
    case nutrition = "Nutrition"
    case toxicology = "Toxicology"
    case musculoskeletal = "Musculoskeletal"
    case rehabilitation = "Rehabilitation"
    case rareDisease = "Rare disease"
    case diagnostic = "Diagnostic"
    case complementary = "Complementary"
    case other = "Other"

    var id: String { rawValue }
}

/// One resolved medication ARIA can coach around. Names and taxonomy only.
struct MedicationContextEntry: Hashable, Sendable, Codable, Identifiable {
    var id: String
    var name: String
    var generic: String
    var brand: String?
    var archetype: String
    var disease: String
    var source: String

    var line: String {
        let names = [brand, generic].compactMap { $0 }.filter { !$0.isEmpty }
        let shown = names.isEmpty ? name : names.joined(separator: " / ")
        return "\(shown) · \(archetype) · \(disease)"
    }
}

/// Medication context layer — Health + saved pharmacy + names mentioned this turn,
/// each resolved against the federal catalog so ARIA knows archetype and disease.
struct MedicationContextLayer: Hashable, Sendable, Codable, Equatable {
    var onFile: [MedicationContextEntry]
    var mentioned: [MedicationContextEntry]
    var archetypes: [String]
    var diseases: [String]

    static let empty = MedicationContextLayer(onFile: [], mentioned: [], archetypes: [], diseases: [])

    var isEmpty: Bool { onFile.isEmpty && mentioned.isEmpty }

    var all: [MedicationContextEntry] { onFile + mentioned }

    var constraintLines: [String] {
        all.prefix(16).map { "med:\($0.source):\($0.archetype):\($0.disease):\($0.generic)" }
    }

    var tags: [String] {
        var tags: [String] = []
        for entry in all {
            tags.append("med_archetype:\(entry.archetype)")
            tags.append("med_disease:\(entry.disease)")
            if entry.source == "health" || entry.source == "saved" {
                tags.append("med_onfile:\(entry.generic)")
            }
        }
        return Array(Set(tags)).sorted()
    }

    var promptBlock: String {
        guard !isEmpty else { return "Medication context: none on file, none mentioned." }
        var lines = ["Medication context layer (federal catalog — brand and generic):"]
        if !onFile.isEmpty {
            lines.append("On file: " + onFile.prefix(12).map(\.line).joined(separator: "; "))
        }
        if !mentioned.isEmpty {
            lines.append("Mentioned this turn: " + mentioned.prefix(8).map(\.line).joined(separator: "; "))
        }
        lines.append("Archetypes: " + archetypes.joined(separator: ", "))
        lines.append("Diseases: " + diseases.joined(separator: ", "))
        lines.append("Coach around these. Never prescribe, never change a dose, never diagnose.")
        return lines.joined(separator: "\n")
    }
}

enum MedicationTaxonomy {
    static let allArchetypes: [String] = MedicationArchetype.allCases.map(\.rawValue)

    static func infer(generic: String, brand: String, form: String) -> (String, String) {
        let blob = "\(generic) \(brand) \(form)".lowercased()
        for (stem, arch, disease) in stems where blob.contains(stem) {
            return (arch, disease)
        }
        if blob.contains("pellet") || blob.contains("tincture") || blob.contains("homeopath") {
            return (MedicationArchetype.complementary.rawValue, "Homeopathic")
        }
        if blob.contains("contrast") || blob.contains("radio") {
            return (MedicationArchetype.diagnostic.rawValue, "Imaging")
        }
        let words = generic.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for word in words {
            for (suffix, arch, disease) in suffixes where word.hasSuffix(suffix) && word.count > suffix.count + 2 {
                return (arch, disease)
            }
        }
        return (MedicationArchetype.other.rawValue, "Unclassified")
    }

    private static let stems: [(String, String, String)] = [
        ("cenobamate", "Neurology", "Epilepsy"),
        ("xcopri", "Neurology", "Epilepsy"),
        ("oxcarbazepine", "Neurology", "Epilepsy"),
        ("oxtellar", "Neurology", "Epilepsy"),
        ("carbamazepine", "Neurology", "Epilepsy"),
        ("lamotrigine", "Neurology", "Epilepsy"),
        ("levetiracetam", "Neurology", "Epilepsy"),
        ("brivaracetam", "Neurology", "Epilepsy"),
        ("topiramate", "Neurology", "Epilepsy"),
        ("phenytoin", "Neurology", "Epilepsy"),
        ("lacosamide", "Neurology", "Epilepsy"),
        ("valpro", "Neurology", "Epilepsy"),
        ("clobazam", "Neurology", "Epilepsy"),
        ("perampanel", "Neurology", "Epilepsy"),
        ("zonisamide", "Neurology", "Epilepsy"),
        ("gabapentin", "Neurology", "Neuropathic pain"),
        ("pregabalin", "Neurology", "Neuropathic pain"),
        ("donepezil", "Neurology", "Alzheimer disease"),
        ("memantine", "Neurology", "Alzheimer disease"),
        ("levodopa", "Neurology", "Parkinson disease"),
        ("carbidopa", "Neurology", "Parkinson disease"),
        ("sumatriptan", "Neurology", "Migraine"),
        ("rizatriptan", "Neurology", "Migraine"),
        ("atorvastatin", "Cardiovascular", "High cholesterol"),
        ("rosuvastatin", "Cardiovascular", "High cholesterol"),
        ("simvastatin", "Cardiovascular", "High cholesterol"),
        ("pravastatin", "Cardiovascular", "High cholesterol"),
        ("lipitor", "Cardiovascular", "High cholesterol"),
        ("crestor", "Cardiovascular", "High cholesterol"),
        ("lisinopril", "Cardiovascular", "Hypertension"),
        ("enalapril", "Cardiovascular", "Hypertension"),
        ("losartan", "Cardiovascular", "Hypertension"),
        ("valsartan", "Cardiovascular", "Hypertension"),
        ("amlodipine", "Cardiovascular", "Hypertension"),
        ("metoprolol", "Cardiovascular", "Hypertension"),
        ("carvedilol", "Cardiovascular", "Heart failure"),
        ("furosemide", "Cardiovascular", "Heart failure"),
        ("apixaban", "Hematology", "Clot prevention"),
        ("rivaroxaban", "Hematology", "Clot prevention"),
        ("warfarin", "Hematology", "Clot prevention"),
        ("clopidogrel", "Cardiovascular", "Clot prevention"),
        ("metformin", "Metabolic", "Diabetes"),
        ("semaglutide", "Metabolic", "Diabetes"),
        ("tirzepatide", "Metabolic", "Diabetes"),
        ("liraglutide", "Metabolic", "Diabetes"),
        ("empagliflozin", "Metabolic", "Diabetes"),
        ("dapagliflozin", "Metabolic", "Diabetes"),
        ("sitagliptin", "Metabolic", "Diabetes"),
        ("insulin", "Metabolic", "Diabetes"),
        ("ozempic", "Metabolic", "Diabetes"),
        ("mounjaro", "Metabolic", "Diabetes"),
        ("glucophage", "Metabolic", "Diabetes"),
        ("levothyroxine", "Endocrine", "Hypothyroidism"),
        ("synthroid", "Endocrine", "Hypothyroidism"),
        ("methimazole", "Endocrine", "Hyperthyroidism"),
        ("sertraline", "Psychiatry", "Depression"),
        ("escitalopram", "Psychiatry", "Depression"),
        ("fluoxetine", "Psychiatry", "Depression"),
        ("duloxetine", "Psychiatry", "Depression"),
        ("bupropion", "Psychiatry", "Depression"),
        ("alprazolam", "Psychiatry", "Anxiety"),
        ("lorazepam", "Psychiatry", "Anxiety"),
        ("aripiprazole", "Psychiatry", "Psychosis"),
        ("quetiapine", "Psychiatry", "Psychosis"),
        ("lithium", "Psychiatry", "Bipolar disorder"),
        ("omeprazole", "Gastroenterology", "Acid reflux"),
        ("pantoprazole", "Gastroenterology", "Acid reflux"),
        ("famotidine", "Gastroenterology", "Acid reflux"),
        ("ondansetron", "Gastroenterology", "Nausea"),
        ("amoxicillin", "Infectious disease", "Bacterial infection"),
        ("azithromycin", "Infectious disease", "Bacterial infection"),
        ("doxycycline", "Infectious disease", "Bacterial infection"),
        ("oseltamivir", "Infectious disease", "Viral infection"),
        ("valacyclovir", "Infectious disease", "Viral infection"),
        ("ibuprofen", "Pain", "Pain and inflammation"),
        ("acetaminophen", "Pain", "Pain and inflammation"),
        ("naproxen", "Pain", "Pain and inflammation"),
        ("hydrocodone", "Pain", "Severe pain"),
        ("oxycodone", "Pain", "Severe pain"),
        ("albuterol", "Respiratory", "Asthma"),
        ("fluticasone", "Respiratory", "Asthma"),
        ("montelukast", "Respiratory", "Asthma"),
        ("tiotropium", "Respiratory", "COPD"),
        ("sildenafil", "Urology", "Erectile dysfunction"),
        ("tadalafil", "Urology", "Erectile dysfunction"),
        ("tamsulosin", "Urology", "Benign prostatic hyperplasia"),
        ("finasteride", "Men's health", "Benign prostatic hyperplasia"),
        ("estradiol", "Women's health", "Hormone therapy"),
        ("progesterone", "Women's health", "Hormone therapy"),
        ("alendronate", "Musculoskeletal", "Osteoporosis"),
        ("allopurinol", "Rheumatology", "Gout"),
        ("adalimumab", "Immunology", "Autoimmune disease"),
        ("methotrexate", "Rheumatology", "Autoimmune disease"),
        ("tacrolimus", "Immunology", "Transplant / autoimmune"),
        ("cyclosporine", "Immunology", "Transplant / autoimmune"),
        ("imatinib", "Oncology", "Cancer"),
        ("tamoxifen", "Oncology", "Breast cancer"),
        ("latanoprost", "Ophthalmology", "Glaucoma"),
        ("timolol", "Ophthalmology", "Glaucoma"),
        ("cetirizine", "Allergy", "Allergy"),
        ("loratadine", "Allergy", "Allergy"),
        ("diphenhydramine", "Allergy", "Allergy"),
        ("zolpidem", "Sleep medicine", "Insomnia"),
        ("eszopiclone", "Sleep medicine", "Insomnia"),
        ("modafinil", "Sleep medicine", "Narcolepsy"),
        ("sennoside", "Gastroenterology", "Constipation"),
        ("polyethylene glycol", "Gastroenterology", "Constipation"),
        ("loperamide", "Gastroenterology", "Diarrhea"),
        ("ondansetron", "Gastroenterology", "Nausea"),
        ("sofosbuvir", "Hepatology", "Hepatitis"),
        ("entecavir", "Hepatology", "Hepatitis"),
        ("sevelamer", "Nephrology", "Chronic kidney disease"),
        ("epoetin", "Hematology", "Anemia"),
        ("ferrous", "Hematology", "Anemia"),
        ("cholecalciferol", "Nutrition", "Vitamin deficiency"),
        ("ergocalciferol", "Nutrition", "Vitamin deficiency"),
        ("cyanocobalamin", "Nutrition", "Vitamin deficiency"),
        ("naloxone", "Toxicology", "Overdose reversal"),
        ("acetylcysteine", "Toxicology", "Overdose reversal"),
        ("vaccine", "Vaccine", "Immunization"),
        ("allergen", "Allergy", "Allergy immunotherapy"),
        ("tretinoin", "Dermatology", "Acne"),
        ("isotretinoin", "Dermatology", "Acne"),
        ("clobetasol", "Dermatology", "Inflammatory skin disease"),
        ("calcipotriene", "Dermatology", "Psoriasis"),
        ("minoxidil", "Dermatology", "Hair loss"),
        ("mupirocin", "Dermatology", "Skin infection"),
        ("oxymetazoline", "Otolaryngology", "Nasal congestion"),
        ("mometasone", "Otolaryngology", "Allergic rhinitis"),
        ("oxytocin", "Obstetrics", "Labor"),
        ("misoprostol", "Obstetrics", "Obstetric care"),
        ("terbutaline", "Obstetrics", "Preterm labor"),
        ("palivizumab", "Pediatrics", "RSV prevention"),
        ("baclofen", "Rehabilitation", "Spasticity"),
        ("tizanidine", "Rehabilitation", "Spasticity"),
        ("cyclobenzaprine", "Musculoskeletal", "Muscle spasm"),
        ("ivacaftor", "Rare disease", "Cystic fibrosis"),
        ("nusinersen", "Rare disease", "Spinal muscular atrophy"),
        ("eculizumab", "Rare disease", "Complement disorder"),
        ("imiglucerase", "Rare disease", "Gaucher disease"),
        ("iohexol", "Diagnostic", "Imaging"),
        ("gadobutrol", "Diagnostic", "Imaging"),
        ("oxybutynin", "Urology", "Overactive bladder"),
        ("solifenacin", "Urology", "Overactive bladder"),
        ("mirabegron", "Urology", "Overactive bladder"),
        ("norethindrone", "Women's health", "Contraception"),
        ("levonorgestrel", "Women's health", "Contraception"),
        ("clomiphene", "Women's health", "Fertility"),
        ("letrozole", "Women's health", "Fertility"),
        ("testosterone", "Men's health", "Hormone therapy"),
        ("melatonin", "Sleep medicine", "Insomnia"),
        ("ramelteon", "Sleep medicine", "Insomnia"),
        ("suvorexant", "Sleep medicine", "Insomnia"),
        ("tramadol", "Pain", "Severe pain"),
        ("morphine", "Pain", "Severe pain"),
        ("celecoxib", "Pain", "Pain and inflammation"),
        ("diclofenac", "Pain", "Pain and inflammation"),
        ("methylphenidate", "Psychiatry", "ADHD"),
        ("lisdexamfetamine", "Psychiatry", "ADHD"),
        ("amphetamine", "Psychiatry", "ADHD"),
        ("riluzole", "Neurology", "ALS"),
        ("interferon beta", "Neurology", "Multiple sclerosis"),
        ("cisplatin", "Oncology", "Cancer"),
        ("paclitaxel", "Oncology", "Cancer"),
        ("doxorubicin", "Oncology", "Cancer"),
        ("tenofovir", "Hepatology", "Hepatitis"),
        ("ribavirin", "Hepatology", "Hepatitis"),
        ("cinacalcet", "Nephrology", "Chronic kidney disease"),
        ("calcitriol", "Nephrology", "Chronic kidney disease"),
        ("enoxaparin", "Hematology", "Clot prevention"),
        ("heparin", "Hematology", "Clot prevention"),
        ("colchicine", "Rheumatology", "Gout"),
        ("hydroxychloroquine", "Rheumatology", "Autoimmune disease"),
        ("mycophenolate", "Immunology", "Transplant / autoimmune"),
        ("prednisone", "Immunology", "Inflammation"),
        ("budesonide", "Respiratory", "Asthma"),
        ("formoterol", "Respiratory", "Asthma"),
        ("theophylline", "Respiratory", "Asthma"),
        ("fexofenadine", "Allergy", "Allergy"),
        ("epinephrine", "Allergy", "Anaphylaxis"),
        ("ascorbic", "Nutrition", "Vitamin deficiency"),
        ("folic acid", "Nutrition", "Vitamin deficiency"),
        ("thiamine", "Nutrition", "Vitamin deficiency"),
        ("flumazenil", "Toxicology", "Overdose reversal"),
        ("fomepizole", "Toxicology", "Overdose reversal"),
        ("denosumab", "Musculoskeletal", "Osteoporosis"),
        ("zoledronic", "Musculoskeletal", "Osteoporosis"),
        ("spironolactone", "Cardiovascular", "Heart failure"),
        ("digoxin", "Cardiovascular", "Heart failure"),
        ("amiodarone", "Cardiovascular", "Arrhythmia"),
        ("nitroglycerin", "Cardiovascular", "Angina"),
        ("glipizide", "Metabolic", "Diabetes"),
        ("pioglitazone", "Metabolic", "Diabetes"),
        ("fluconazole", "Infectious disease", "Fungal infection"),
        ("metronidazole", "Infectious disease", "Bacterial infection"),
        ("nitrofurantoin", "Infectious disease", "Urinary tract infection"),
    ]

    private static let suffixes: [(String, String, String)] = [
        ("statin", "Cardiovascular", "High cholesterol"),
        ("sartan", "Cardiovascular", "Hypertension"),
        ("pril", "Cardiovascular", "Hypertension"),
        ("olol", "Cardiovascular", "Hypertension"),
        ("dipine", "Cardiovascular", "Hypertension"),
        ("prazole", "Gastroenterology", "Acid reflux"),
        ("tidine", "Gastroenterology", "Acid reflux"),
        ("cillin", "Infectious disease", "Bacterial infection"),
        ("cycline", "Infectious disease", "Bacterial infection"),
        ("floxacin", "Infectious disease", "Bacterial infection"),
        ("conazole", "Infectious disease", "Fungal infection"),
        ("mycin", "Infectious disease", "Bacterial infection"),
        ("navir", "Infectious disease", "Viral infection"),
        ("tegravir", "Infectious disease", "Viral infection"),
        ("vir", "Infectious disease", "Viral infection"),
        ("azepam", "Psychiatry", "Anxiety"),
        ("azolam", "Psychiatry", "Anxiety"),
        ("oxetine", "Psychiatry", "Depression"),
        ("pramine", "Psychiatry", "Depression"),
        ("caine", "Pain", "Local anesthesia"),
        ("codone", "Pain", "Severe pain"),
        ("dronate", "Musculoskeletal", "Osteoporosis"),
        ("afil", "Urology", "Erectile dysfunction"),
        ("parin", "Hematology", "Clot prevention"),
        ("triptan", "Neurology", "Migraine"),
        ("gliptin", "Metabolic", "Diabetes"),
        ("gliflozin", "Metabolic", "Diabetes"),
        ("glutide", "Metabolic", "Diabetes"),
        ("mab", "Immunology", "Autoimmune disease"),
        ("nib", "Oncology", "Cancer"),
        ("prost", "Ophthalmology", "Glaucoma"),
    ]
}

enum MedicationContext {
    static func resolve(
        query: String? = nil,
        healthNames: [String] = [],
        savedNames: [String] = []
    ) -> MedicationContextLayer {
        var seen = Set<String>()
        var onFile: [MedicationContextEntry] = []
        var mentioned: [MedicationContextEntry] = []

        for name in healthNames {
            if let entry = lookup(name, source: "health"), seen.insert(entry.id).inserted {
                onFile.append(entry)
            }
        }
        for name in savedNames {
            if let entry = lookup(name, source: "saved"), seen.insert(entry.id).inserted {
                onFile.append(entry)
            }
        }
        for token in mentionTokens(query) {
            if let entry = lookup(token, source: "mentioned"), seen.insert(entry.id).inserted {
                mentioned.append(entry)
            }
        }

        let all = onFile + mentioned
        let archetypes = Array(Set(all.map(\.archetype))).sorted()
        let diseases = Array(Set(all.map(\.disease))).sorted()
        return MedicationContextLayer(
            onFile: Array(onFile.prefix(20)),
            mentioned: Array(mentioned.prefix(12)),
            archetypes: archetypes,
            diseases: diseases
        )
    }

    private static func lookup(_ raw: String, source: String) -> MedicationContextEntry? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return nil }
        // Views call resolve during layout. Never inflate the catalog here —
        // AriaService.prepare() loads it before a chat turn.
        let hit: FDAMedication? = MedicationPharmacy.isReady
            ? MedicationPharmacy.search(q, sort: .relevance, limit: 1).items.first
            : nil
        guard let hit else {
            let inferred = MedicationTaxonomy.infer(generic: q, brand: "", form: "")
            guard inferred.0 != MedicationArchetype.other.rawValue || q.count >= 5 else { return nil }
            return MedicationContextEntry(
                id: "\(source):\(q.lowercased())",
                name: q,
                generic: q,
                brand: nil,
                archetype: inferred.0,
                disease: inferred.1,
                source: source
            )
        }
        let brandMatch = hit.brand?.localizedCaseInsensitiveContains(q) == true
        let genericMatch = hit.generic.localizedCaseInsensitiveContains(q)
        let nameMatch = hit.name.localizedCaseInsensitiveContains(q)
        guard brandMatch || genericMatch || nameMatch || source != "mentioned" else { return nil }
        return MedicationContextEntry(
            id: "\(source):\(hit.id)",
            name: hit.name,
            generic: hit.generic,
            brand: hit.brand,
            archetype: hit.archetype,
            disease: hit.disease,
            source: source
        )
    }

    private static func mentionTokens(_ query: String?) -> [String] {
        guard let query, !query.isEmpty else { return [] }
        return query
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= 4 }
    }
}
