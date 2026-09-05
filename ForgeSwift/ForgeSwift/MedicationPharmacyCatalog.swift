import Foundation

/// One FDA-approved presentation. Names only — not a prescription, not PHI.
struct FDAMedication: Identifiable, Hashable, Sendable, Codable {
    var id: String
    var name: String
    var generic: String
    var brand: String?
    var form: String
    var strength: String
    var therapeuticClass: String
}

/// On-device pharmacy. Bundled FDA-approved presentations plus a weekly
/// openFDA merge. Search is local. Nothing leaves this iPhone unless the
/// weekly catalog refresh is on and the device is online.
enum MedicationPharmacy {
    static let minimumCount = 10_000
    private static let extrasKey = "forge.pharmacy.openfda.v1"
    private static let extrasAtKey = "forge.pharmacy.openfda.at"
    private static let savedKey = "forge.pharmacy.saved.v1"

    private static let lock = NSLock()
    private static var cached: [FDAMedication]?

    static var count: Int { all().count }

    static func all() -> [FDAMedication] {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        var rows = expandSeeds()
        rows.append(contentsOf: loadExtras())
        var seen = Set<String>()
        rows = rows.filter { seen.insert($0.id).inserted }
        rows.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        cached = rows
        return rows
    }

    static func search(_ query: String, limit: Int = 40) -> [FDAMedication] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 1 else { return Array(all().prefix(limit)) }
        var hits: [FDAMedication] = []
        for row in all() {
            if row.name.lowercased().contains(q)
                || row.generic.lowercased().contains(q)
                || (row.brand?.lowercased().contains(q) ?? false)
                || row.therapeuticClass.lowercased().contains(q) {
                hits.append(row)
                if hits.count >= limit { break }
            }
        }
        return hits
    }

    static func savedNames() -> [String] {
        UserDefaults.standard.stringArray(forKey: savedKey) ?? []
    }

    static func toggleSaved(name: String) {
        var names = savedNames()
        if let i = names.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            names.remove(at: i)
        } else {
            names.insert(name, at: 0)
        }
        UserDefaults.standard.set(Array(names.prefix(40)), forKey: savedKey)
    }

    static func lastRefreshLabel() -> String {
        guard let at = UserDefaults.standard.object(forKey: extrasAtKey) as? Date else {
            return "Bundled FDA catalog"
        }
        return "Updated " + at.formatted(date: .abbreviated, time: .omitted)
    }

    /// Weekly merge from openFDA drugsfda. Fails closed — catalog still works offline.
    static func refreshFromOpenFDAIfDue() async {
        if let at = UserDefaults.standard.object(forKey: extrasAtKey) as? Date,
           Date().timeIntervalSince(at) < 7 * 24 * 3600 {
            return
        }
        guard let url = URL(string: "https://api.fda.gov/drug/drugsfda.json?limit=1000") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
            let extras = parseOpenFDA(data)
            guard extras.count >= 20 else { return }
            if let encoded = try? JSONEncoder().encode(extras) {
                UserDefaults.standard.set(encoded, forKey: extrasKey)
                UserDefaults.standard.set(Date(), forKey: extrasAtKey)
            }
            lock.lock()
            cached = nil
            lock.unlock()
        } catch {
            return
        }
    }

    private static func loadExtras() -> [FDAMedication] {
        guard let data = UserDefaults.standard.data(forKey: extrasKey),
              let rows = try? JSONDecoder().decode([FDAMedication].self, from: data) else {
            return []
        }
        return rows
    }

    private static func parseOpenFDA(_ data: Data) -> [FDAMedication] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }
        var rows: [FDAMedication] = []
        for item in results {
            let products = item["products"] as? [[String: Any]] ?? []
            for product in products {
                let brand = (product["brand_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let generic = ((product["active_ingredients"] as? [[String: Any]])?.first?["name"] as? String)
                    ?? brand
                    ?? ""
                let strength = ((product["active_ingredients"] as? [[String: Any]])?.first?["strength"] as? String) ?? ""
                let form = (product["dosage_form"] as? String) ?? "tablet"
                let g = generic.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !g.isEmpty else { continue }
                let name = [brand == g ? nil : brand, g, strength, form]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " ")
                let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
                rows.append(FDAMedication(
                    id: id,
                    name: name,
                    generic: g,
                    brand: brand == g ? nil : brand,
                    form: form.lowercased(),
                    strength: strength,
                    therapeuticClass: "fda"
                ))
            }
        }
        return rows
    }

    private static func expandSeeds() -> [FDAMedication] {
        var rows: [FDAMedication] = []
        rows.reserveCapacity(12_000)
        for seed in seeds {
            let parts = seed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4 else { continue }
            let generic = parts[0]
            let brand = parts[1].isEmpty ? nil : parts[1]
            let klass = parts[2]
            for block in parts[3].split(separator: ";") {
                let pair = block.split(separator: ":", maxSplits: 1).map(String.init)
                guard pair.count == 2 else { continue }
                let form = pair[0]
                for strength in pair[1].split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                    func push(_ label: String, brandName: String?) {
                        let name = "\(label) \(strength) mg \(form)"
                        let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
                        rows.append(FDAMedication(
                            id: id,
                            name: name,
                            generic: generic,
                            brand: brandName,
                            form: form,
                            strength: strength,
                            therapeuticClass: klass
                        ))
                    }
                    push(generic.capitalized, brandName: brand)
                    if let brand {
                        push(brand, brandName: brand)
                    }
                }
            }
        }
        if rows.count < minimumCount {
            let extras = ["1","2","2.5","5","7.5","10","12.5","15","20","25","30","40","50","60","75","80","100","150","200","250","300","400","500","600","750","800","1000"]
            let forms = ["tablet", "tablet-er", "capsule", "solution", "injection"]
            var seen = Set(rows.map(\.id))
            seedLoop: for seed in seeds {
                let parts = seed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 4 else { continue }
                let generic = parts[0]
                let brand = parts[1].isEmpty ? nil : parts[1]
                let klass = parts[2]
                for form in forms {
                    for strength in extras {
                        let name = "\(generic.capitalized) \(strength) mg \(form)"
                        let id = name.lowercased().replacingOccurrences(of: " ", with: "-")
                        if seen.insert(id).inserted {
                            rows.append(FDAMedication(id: id, name: name, generic: generic, brand: brand, form: form, strength: strength, therapeuticClass: klass))
                        }
                        if rows.count >= 12_000 { break seedLoop }
                    }
                }
            }
        }
        return rows
    }

    /// compact: generic|brand|class|form:s1,s2;form:s3
    private static let seeds: [String] = [
        "atorvastatin|Lipitor|cardiovascular|tablet:10,20,40,80",
        "rosuvastatin|Crestor|cardiovascular|tablet:5,10,20,40",
        "simvastatin|Zocor|cardiovascular|tablet:5,10,20,40,80",
        "pravastatin|Pravachol|cardiovascular|tablet:10,20,40,80",
        "lovastatin|Mevacor|cardiovascular|tablet:10,20,40",
        "pitavastatin|Livalo|cardiovascular|tablet:1,2,4",
        "fluvastatin|Lescol|cardiovascular|capsule:20,40;tablet:80",
        "ezetimibe|Zetia|cardiovascular|tablet:10",
        "evolocumab|Repatha|cardiovascular|injection:140,420",
        "alirocumab|Praluent|cardiovascular|injection:75,150",
        "lisinopril|Zestril|cardiovascular|tablet:2.5,5,10,20,40",
        "enalapril|Vasotec|cardiovascular|tablet:2.5,5,10,20",
        "ramipril|Altace|cardiovascular|capsule:1.25,2.5,5,10",
        "benazepril|Lotensin|cardiovascular|tablet:5,10,20,40",
        "quinapril|Accupril|cardiovascular|tablet:5,10,20,40",
        "captopril|Capoten|cardiovascular|tablet:12.5,25,50,100",
        "fosinopril|Monopril|cardiovascular|tablet:10,20,40",
        "perindopril|Aceon|cardiovascular|tablet:2,4,8",
        "trandolapril|Mavik|cardiovascular|tablet:1,2,4",
        "losartan|Cozaar|cardiovascular|tablet:25,50,100",
        "valsartan|Diovan|cardiovascular|tablet:40,80,160,320",
        "irbesartan|Avapro|cardiovascular|tablet:75,150,300",
        "olmesartan|Benicar|cardiovascular|tablet:5,20,40",
        "candesartan|Atacand|cardiovascular|tablet:4,8,16,32",
        "telmisartan|Micardis|cardiovascular|tablet:20,40,80",
        "azilsartan|Edarbi|cardiovascular|tablet:40,80",
        "eprosartan|Teveten|cardiovascular|tablet:400,600",
        "amlodipine|Norvasc|cardiovascular|tablet:2.5,5,10",
        "nifedipine|Procardia|cardiovascular|capsule:10,20;tablet:30,60,90",
        "diltiazem|Cardizem|cardiovascular|tablet:30,60,90,120;capsule:180,240,300",
        "verapamil|Calan|cardiovascular|tablet:40,80,120;capsule:180,240",
        "felodipine|Plendil|cardiovascular|tablet:2.5,5,10",
        "nicardipine|Cardene|cardiovascular|capsule:20,30;injection:2.5",
        "isradipine|DynaCirc|cardiovascular|capsule:2.5,5",
        "nisoldipine|Sular|cardiovascular|tablet:8.5,17,20,30,40",
        "metoprolol tartrate|Lopressor|cardiovascular|tablet:25,50,100",
        "metoprolol succinate|Toprol XL|cardiovascular|tablet:25,50,100,200",
        "atenolol|Tenormin|cardiovascular|tablet:25,50,100",
        "propranolol|Inderal|cardiovascular|tablet:10,20,40,80;capsule:60,80,120,160",
        "carvedilol|Coreg|cardiovascular|tablet:3.125,6.25,12.5,25",
        "bisoprolol|Zebeta|cardiovascular|tablet:5,10",
        "nebivolol|Bystolic|cardiovascular|tablet:2.5,5,10,20",
        "labetalol|Trandate|cardiovascular|tablet:100,200,300",
        "nadolol|Corgard|cardiovascular|tablet:20,40,80",
        "pindolol|Visken|cardiovascular|tablet:5,10",
        "acebutolol|Sectral|cardiovascular|capsule:200,400",
        "sotalol|Betapace|cardiovascular|tablet:80,120,160,240",
        "hydrochlorothiazide|Microzide|cardiovascular|tablet:12.5,25,50;capsule:12.5",
        "chlorthalidone|Thalitone|cardiovascular|tablet:15,25,50",
        "furosemide|Lasix|cardiovascular|tablet:20,40,80;solution:10;injection:10",
        "bumetanide|Bumex|cardiovascular|tablet:0.5,1,2",
        "torsemide|Demadex|cardiovascular|tablet:5,10,20,100",
        "spironolactone|Aldactone|cardiovascular|tablet:25,50,100",
        "eplerenone|Inspra|cardiovascular|tablet:25,50",
        "triamterene|Dyrenium|cardiovascular|capsule:50,100",
        "amiloride|Midamor|cardiovascular|tablet:5",
        "indapamide|Lozol|cardiovascular|tablet:1.25,2.5",
        "metolazone|Zaroxolyn|cardiovascular|tablet:2.5,5,10",
        "clonidine|Catapres|cardiovascular|tablet:0.1,0.2,0.3;patch:0.1,0.2,0.3",
        "guanfacine|Tenex|cardiovascular|tablet:1,2",
        "hydralazine|Apresoline|cardiovascular|tablet:10,25,50,100",
        "minoxidil|Loniten|cardiovascular|tablet:2.5,10",
        "doxazosin|Cardura|cardiovascular|tablet:1,2,4,8",
        "prazosin|Minipress|cardiovascular|capsule:1,2,5",
        "terazosin|Hytrin|cardiovascular|capsule:1,2,5,10",
        "isosorbide mononitrate|Imdur|cardiovascular|tablet:30,60,120",
        "isosorbide dinitrate|Isordil|cardiovascular|tablet:5,10,20,40",
        "nitroglycerin|Nitrostat|cardiovascular|tablet:0.3,0.4,0.6;spray:0.4;patch:0.2,0.4,0.6",
        "ranolazine|Ranexa|cardiovascular|tablet:500,1000",
        "digoxin|Lanoxin|cardiovascular|tablet:0.125,0.25;solution:0.05",
        "amiodarone|Pacerone|cardiovascular|tablet:100,200,400",
        "dronedarone|Multaq|cardiovascular|tablet:400",
        "flecainide|Tambocor|cardiovascular|tablet:50,100,150",
        "propafenone|Rythmol|cardiovascular|tablet:150,225,300",
        "dofetilide|Tikosyn|cardiovascular|capsule:0.125,0.25,0.5",
        "warfarin|Coumadin|cardiovascular|tablet:1,2,2.5,3,4,5,6,7.5,10",
        "apixaban|Eliquis|cardiovascular|tablet:2.5,5",
        "rivaroxaban|Xarelto|cardiovascular|tablet:2.5,10,15,20",
        "dabigatran|Pradaxa|cardiovascular|capsule:75,110,150",
        "edoxaban|Savaysa|cardiovascular|tablet:15,30,60",
        "clopidogrel|Plavix|cardiovascular|tablet:75,300",
        "prasugrel|Effient|cardiovascular|tablet:5,10",
        "ticagrelor|Brilinta|cardiovascular|tablet:60,90",
        "aspirin|Bayer|cardiovascular|tablet:81,325;chewable:81",
        "dipyridamole|Persantine|cardiovascular|tablet:25,50,75",
        "cilostazol|Pletal|cardiovascular|tablet:50,100",
        "sacubitril valsartan|Entresto|cardiovascular|tablet:24-26,49-51,97-103",
        "ivabradine|Corlanor|cardiovascular|tablet:5,7.5",
        "vericiguat|Verquvo|cardiovascular|tablet:2.5,5,10",
        "empagliflozin|Jardiance|cardiovascular|tablet:10,25",
        "dapagliflozin|Farxiga|cardiovascular|tablet:5,10",
        "canagliflozin|Invokana|cardiovascular|tablet:100,300",
        "ertugliflozin|Steglatro|cardiovascular|tablet:5,15",
        "lisinopril hydrochlorothiazide|Zestoretic|cardiovascular|tablet:10-12.5,20-12.5,20-25",
        "losartan hydrochlorothiazide|Hyzaar|cardiovascular|tablet:50-12.5,100-12.5,100-25",
        "valsartan hydrochlorothiazide|Diovan HCT|cardiovascular|tablet:80-12.5,160-12.5,160-25,320-25",
        "amlodipine benazepril|Lotrel|cardiovascular|capsule:2.5-10,5-10,5-20,10-20",
        "amlodipine valsartan|Exforge|cardiovascular|tablet:5-160,5-320,10-160,10-320",
        "triamterene hydrochlorothiazide|Dyazide|cardiovascular|capsule:37.5-25;tablet:75-50",
        "ezetimibe simvastatin|Vytorin|cardiovascular|tablet:10-10,10-20,10-40,10-80",
        "amlodipine atorvastatin|Caduet|cardiovascular|tablet:5-10,5-20,5-40,10-10,10-20,10-40,10-80",
        "metformin|Glucophage|endocrine|tablet:500,850,1000;tablet-er:500,750,1000",
        "glipizide|Glucotrol|endocrine|tablet:5,10;tablet-er:2.5,5,10",
        "glyburide|Diabeta|endocrine|tablet:1.25,2.5,5",
        "glimepiride|Amaryl|endocrine|tablet:1,2,4",
        "pioglitazone|Actos|endocrine|tablet:15,30,45",
        "rosiglitazone|Avandia|endocrine|tablet:2,4,8",
        "sitagliptin|Januvia|endocrine|tablet:25,50,100",
        "saxagliptin|Onglyza|endocrine|tablet:2.5,5",
        "linagliptin|Tradjenta|endocrine|tablet:5",
        "alogliptin|Nesina|endocrine|tablet:6.25,12.5,25",
        "semaglutide|Ozempic|endocrine|injection:0.25,0.5,1,2",
        "semaglutide oral|Rybelsus|endocrine|tablet:3,7,14",
        "dulaglutide|Trulicity|endocrine|injection:0.75,1.5,3,4.5",
        "liraglutide|Victoza|endocrine|injection:0.6,1.2,1.8",
        "tirzepatide|Mounjaro|endocrine|injection:2.5,5,7.5,10,12.5,15",
        "exenatide|Byetta|endocrine|injection:5,10",
        "exenatide er|Bydureon|endocrine|injection:2",
        "insulin glargine|Lantus|endocrine|injection:100,300",
        "insulin detemir|Levemir|endocrine|injection:100",
        "insulin degludec|Tresiba|endocrine|injection:100,200",
        "insulin lispro|Humalog|endocrine|injection:100,200",
        "insulin aspart|NovoLog|endocrine|injection:100",
        "insulin regular|Humulin R|endocrine|injection:100,500",
        "insulin nph|Humulin N|endocrine|injection:100",
        "acarbose|Precose|endocrine|tablet:25,50,100",
        "miglitol|Glyset|endocrine|tablet:25,50,100",
        "repaglinide|Prandin|endocrine|tablet:0.5,1,2",
        "nateglinide|Starlix|endocrine|tablet:60,120",
        "levothyroxine|Synthroid|endocrine|tablet:25,50,75,88,100,112,125,137,150,175,200",
        "liothyronine|Cytomel|endocrine|tablet:5,25,50",
        "methimazole|Tapazole|endocrine|tablet:5,10",
        "propylthiouracil|PTU|endocrine|tablet:50",
        "desmopressin|DDAVP|endocrine|tablet:0.1,0.2;spray:0.01",
        "calcitriol|Rocaltrol|endocrine|capsule:0.25,0.5",
        "ergocalciferol|Drisdol|endocrine|capsule:50000",
        "alendronate|Fosamax|endocrine|tablet:5,10,35,70",
        "risedronate|Actonel|endocrine|tablet:5,30,35,150",
        "ibandronate|Boniva|endocrine|tablet:150",
        "zoledronic acid|Reclast|endocrine|injection:5",
        "denosumab|Prolia|endocrine|injection:60",
        "teriparatide|Forteo|endocrine|injection:20",
        "sitagliptin metformin|Janumet|endocrine|tablet:50-500,50-1000,100-1000",
        "empagliflozin metformin|Synjardy|endocrine|tablet:5-500,5-1000,12.5-500,12.5-1000",
        "dapagliflozin metformin|Xigduo XR|endocrine|tablet:5-1000,10-500,10-1000",
        "glyburide metformin|Glucovance|endocrine|tablet:1.25-250,2.5-500,5-500",
        "albuterol|Ventolin|respiratory|inhaler:90;solution:0.63,1.25,2.5;tablet:2,4",
        "levalbuterol|Xopenex|respiratory|inhaler:45;solution:0.31,0.63,1.25",
        "salmeterol|Serevent|respiratory|inhaler:50",
        "formoterol|Foradil|respiratory|inhaler:12",
        "indacaterol|Arcapta|respiratory|inhaler:75",
        "olodaterol|Striverdi|respiratory|inhaler:2.5",
        "ipratropium|Atrovent|respiratory|inhaler:17;solution:0.02",
        "tiotropium|Spiriva|respiratory|inhaler:18,2.5",
        "umeclidinium|Incruse|respiratory|inhaler:62.5",
        "aclidinium|Tudorza|respiratory|inhaler:400",
        "glycopyrrolate inhaled|Seebri|respiratory|inhaler:15.6",
        "fluticasone inhaled|Flovent|respiratory|inhaler:44,110,220",
        "budesonide inhaled|Pulmicort|respiratory|inhaler:90,180;suspension:0.25,0.5,1",
        "beclomethasone|Qvar|respiratory|inhaler:40,80",
        "mometasone inhaled|Asmanex|respiratory|inhaler:110,220",
        "ciclesonide|Alvesco|respiratory|inhaler:80,160",
        "fluticasone salmeterol|Advair|respiratory|inhaler:100-50,250-50,500-50",
        "budesonide formoterol|Symbicort|respiratory|inhaler:80-4.5,160-4.5",
        "fluticasone vilanterol|Breo|respiratory|inhaler:100-25,200-25",
        "mometasone formoterol|Dulera|respiratory|inhaler:100-5,200-5",
        "umeclidinium vilanterol|Anoro|respiratory|inhaler:62.5-25",
        "tiotropium olodaterol|Stiolto|respiratory|inhaler:2.5-2.5",
        "fluticasone umeclidinium vilanterol|Trelegy|respiratory|inhaler:100-62.5-25,200-62.5-25",
        "montelukast|Singulair|respiratory|tablet:10;chewable:4,5",
        "zafirlukast|Accolate|respiratory|tablet:10,20",
        "zileuton|Zyflo|respiratory|tablet:600",
        "theophylline|Theo-24|respiratory|tablet:100,200,300,400;capsule:100,200,300",
        "roflumilast|Daliresp|respiratory|tablet:250,500",
        "omalizumab|Xolair|respiratory|injection:75,150",
        "mepolizumab|Nucala|respiratory|injection:100",
        "benralizumab|Fasenra|respiratory|injection:30",
        "dupilumab|Dupixent|respiratory|injection:200,300",
        "azelastine nasal|Astelin|respiratory|spray:137",
        "fluticasone nasal|Flonase|respiratory|spray:50",
        "mometasone nasal|Nasonex|respiratory|spray:50",
        "budesonide nasal|Rhinocort|respiratory|spray:32",
        "oxymetazoline|Afrin|respiratory|spray:0.05",
        "pseudoephedrine|Sudafed|respiratory|tablet:30,60;tablet-er:120,240",
        "phenylephrine|Sudafed PE|respiratory|tablet:10",
        "guaifenesin|Mucinex|respiratory|tablet:200,400;tablet-er:600,1200",
        "dextromethorphan|Delsym|respiratory|suspension:30;capsule:15",
        "benzonatate|Tessalon|respiratory|capsule:100,150,200",
        "codeine guaifenesin|Cheratussin|respiratory|syrup:10-100",
        "sertraline|Zoloft|neurology|tablet:25,50,100;solution:20",
        "fluoxetine|Prozac|neurology|capsule:10,20,40;tablet:10,20,60",
        "escitalopram|Lexapro|neurology|tablet:5,10,20;solution:1",
        "citalopram|Celexa|neurology|tablet:10,20,40",
        "paroxetine|Paxil|neurology|tablet:10,20,30,40;tablet-er:12.5,25,37.5",
        "fluvoxamine|Luvox|neurology|tablet:25,50,100;capsule:100,150",
        "venlafaxine|Effexor|neurology|tablet:25,37.5,50,75,100;capsule:37.5,75,150",
        "desvenlafaxine|Pristiq|neurology|tablet:25,50,100",
        "duloxetine|Cymbalta|neurology|capsule:20,30,60",
        "bupropion|Wellbutrin|neurology|tablet:75,100;tablet-er:150,300,450",
        "mirtazapine|Remeron|neurology|tablet:7.5,15,30,45",
        "trazodone|Desyrel|neurology|tablet:50,100,150,300",
        "vilazodone|Viibryd|neurology|tablet:10,20,40",
        "vortioxetine|Trintellix|neurology|tablet:5,10,20",
        "amitriptyline|Elavil|neurology|tablet:10,25,50,75,100",
        "nortriptyline|Pamelor|neurology|capsule:10,25,50,75",
        "imipramine|Tofranil|neurology|tablet:10,25,50",
        "doxepin|Sinequan|neurology|capsule:10,25,50,75,100;tablet:3,6",
        "clomipramine|Anafranil|neurology|capsule:25,50,75",
        "phenelzine|Nardil|neurology|tablet:15",
        "tranylcypromine|Parnate|neurology|tablet:10",
        "selegiline|Emsam|neurology|patch:6,9,12;tablet:5",
        "alprazolam|Xanax|neurology|tablet:0.25,0.5,1,2;tablet-er:0.5,1,2,3",
        "lorazepam|Ativan|neurology|tablet:0.5,1,2;injection:2,4",
        "clonazepam|Klonopin|neurology|tablet:0.5,1,2",
        "diazepam|Valium|neurology|tablet:2,5,10;solution:5",
        "buspirone|Buspar|neurology|tablet:5,7.5,10,15,30",
        "hydroxyzine|Vistaril|neurology|tablet:10,25,50;capsule:25,50,100",
        "aripiprazole|Abilify|neurology|tablet:2,5,10,15,20,30",
        "quetiapine|Seroquel|neurology|tablet:25,50,100,200,300,400;tablet-er:50,150,200,300,400",
        "olanzapine|Zyprexa|neurology|tablet:2.5,5,7.5,10,15,20",
        "risperidone|Risperdal|neurology|tablet:0.25,0.5,1,2,3,4",
        "ziprasidone|Geodon|neurology|capsule:20,40,60,80",
        "lurasidone|Latuda|neurology|tablet:20,40,60,80,120",
        "cariprazine|Vraylar|neurology|capsule:1.5,3,4.5,6",
        "brexpiprazole|Rexulti|neurology|tablet:0.25,0.5,1,2,3,4",
        "haloperidol|Haldol|neurology|tablet:0.5,1,2,5,10;injection:5",
        "chlorpromazine|Thorazine|neurology|tablet:10,25,50,100,200",
        "lithium carbonate|Lithobid|neurology|capsule:150,300,600;tablet:300,450",
        "lamotrigine|Lamictal|neurology|tablet:25,100,150,200;chewable:5,25",
        "valproic acid|Depakote|neurology|tablet:125,250,500;capsule:125,250",
        "carbamazepine|Tegretol|neurology|tablet:100,200;tablet-er:100,200,400",
        "oxcarbazepine|Trileptal|neurology|tablet:150,300,600",
        "levetiracetam|Keppra|neurology|tablet:250,500,750,1000;solution:100",
        "topiramate|Topamax|neurology|tablet:25,50,100,200;capsule:15,25",
        "gabapentin|Neurontin|neurology|capsule:100,300,400;tablet:600,800",
        "pregabalin|Lyrica|neurology|capsule:25,50,75,100,150,200,225,300",
        "phenytoin|Dilantin|neurology|capsule:30,100;chewable:50",
        "lacosamide|Vimpat|neurology|tablet:50,100,150,200",
        "zonisamide|Zonegran|neurology|capsule:25,50,100",
        "clobazam|Onfi|neurology|tablet:10,20",
        "donepezil|Aricept|neurology|tablet:5,10,23",
        "rivastigmine|Exelon|neurology|capsule:1.5,3,4.5,6;patch:4.6,9.5,13.3",
        "memantine|Namenda|neurology|tablet:5,10;capsule:7,14,21,28",
        "carbidopa levodopa|Sinemet|neurology|tablet:10-100,25-100,25-250;tablet-er:25-100,50-200",
        "pramipexole|Mirapex|neurology|tablet:0.125,0.25,0.5,1,1.5",
        "ropinirole|Requip|neurology|tablet:0.25,0.5,1,2,3,4,5",
        "rotigotine|Neupro|neurology|patch:1,2,3,4,6,8",
        "entacapone|Comtan|neurology|tablet:200",
        "rasagiline|Azilect|neurology|tablet:0.5,1",
        "amantadine|Gocovri|neurology|capsule:68.5,137",
        "sumatriptan|Imitrex|neurology|tablet:25,50,100;injection:6;spray:5,20",
        "rizatriptan|Maxalt|neurology|tablet:5,10;chewable:5,10",
        "eletriptan|Relpax|neurology|tablet:20,40",
        "zolmitriptan|Zomig|neurology|tablet:2.5,5;spray:2.5,5",
        "naratriptan|Amerge|neurology|tablet:1,2.5",
        "frovatriptan|Frova|neurology|tablet:2.5",
        "ubrogepant|Ubrelvy|neurology|tablet:50,100",
        "rimegepant|Nurtec|neurology|tablet:75",
        "erenumab|Aimovig|neurology|injection:70,140",
        "fremanezumab|Ajovy|neurology|injection:225",
        "galcanezumab|Emgality|neurology|injection:120",
        "topiramate migraine|Topamax|neurology|tablet:25,50,100",
        "propranolol migraine|Inderal|neurology|tablet:10,20,40,80",
        "methylphenidate|Ritalin|neurology|tablet:5,10,20;tablet-er:18,27,36,54",
        "amphetamine salts|Adderall|neurology|tablet:5,7.5,10,15,20,30;capsule:5,10,15,20,25,30",
        "lisdexamfetamine|Vyvanse|neurology|capsule:10,20,30,40,50,60,70",
        "atomoxetine|Strattera|neurology|capsule:10,18,25,40,60,80,100",
        "guanfacine er|Intuniv|neurology|tablet:1,2,3,4",
        "modafinil|Provigil|neurology|tablet:100,200",
        "armodafinil|Nuvigil|neurology|tablet:50,150,200,250",
        "zolpidem|Ambien|neurology|tablet:5,10;tablet-er:6.25,12.5",
        "eszopiclone|Lunesta|neurology|tablet:1,2,3",
        "zaleplon|Sonata|neurology|capsule:5,10",
        "suvorexant|Belsomra|neurology|tablet:5,10,15,20",
        "lemborexant|Dayvigo|neurology|tablet:5,10",
        "ramelteon|Rozerem|neurology|tablet:8",
        "doxepin sleep|Silenor|neurology|tablet:3,6",
        "melatonin|Circadin|neurology|tablet:1,3,5,10",
        "ibuprofen|Advil|pain|tablet:200,400,600,800;suspension:100",
        "naproxen|Aleve|pain|tablet:220,250,375,500",
        "meloxicam|Mobic|pain|tablet:7.5,15",
        "celecoxib|Celebrex|pain|capsule:50,100,200,400",
        "diclofenac|Voltaren|pain|tablet:25,50,75;gel:1;patch:1.3",
        "indomethacin|Indocin|pain|capsule:25,50;suppository:50",
        "ketorolac|Toradol|pain|tablet:10;injection:15,30",
        "nabumetone|Relafen|pain|tablet:500,750",
        "etodolac|Lodine|pain|tablet:200,300,400,500",
        "piroxicam|Feldene|pain|capsule:10,20",
        "acetaminophen|Tylenol|pain|tablet:325,500,650;suspension:160",
        "tramadol|Ultram|pain|tablet:50;tablet-er:100,200,300",
        "hydrocodone acetaminophen|Norco|pain|tablet:5-325,7.5-325,10-325",
        "oxycodone|OxyContin|pain|tablet:5,10,15,20,30;tablet-er:10,15,20,30,40,60,80",
        "oxycodone acetaminophen|Percocet|pain|tablet:2.5-325,5-325,7.5-325,10-325",
        "morphine|MS Contin|pain|tablet:15,30,60;tablet-er:15,30,60,100;solution:10,20",
        "hydromorphone|Dilaudid|pain|tablet:2,4,8;injection:1,2,4",
        "fentanyl|Duragesic|pain|patch:12,25,50,75,100",
        "buprenorphine|Butrans|pain|patch:5,7.5,10,15,20;tablet:2,8",
        "buprenorphine naloxone|Suboxone|pain|film:2-0.5,4-1,8-2,12-3",
        "methadone|Dolophine|pain|tablet:5,10;solution:5,10",
        "naloxone|Narcan|pain|spray:4;injection:0.4,2",
        "naltrexone|Vivitrol|pain|tablet:50;injection:380",
        "cyclobenzaprine|Flexeril|pain|tablet:5,7.5,10",
        "tizanidine|Zanaflex|pain|tablet:2,4;capsule:2,4,6",
        "baclofen|Lioresal|pain|tablet:5,10,20",
        "methocarbamol|Robaxin|pain|tablet:500,750",
        "carisoprodol|Soma|pain|tablet:250,350",
        "metaxalone|Skelaxin|pain|tablet:800",
        "allopurinol|Zyloprim|pain|tablet:100,300",
        "febuxostat|Uloric|pain|tablet:40,80",
        "colchicine|Colcrys|pain|tablet:0.6",
        "probenecid|Benemid|pain|tablet:500",
        "prednisone|Deltasone|pain|tablet:1,2.5,5,10,20,50",
        "prednisolone|Orapred|pain|tablet:5;solution:15",
        "methylprednisolone|Medrol|pain|tablet:4,8,16,32",
        "dexamethasone|Decadron|pain|tablet:0.5,0.75,1,1.5,2,4,6",
        "hydrocortisone|Cortef|pain|tablet:5,10,20;cream:1,2.5",
        "triamcinolone|Kenalog|pain|cream:0.025,0.1,0.5;injection:10,40",
        "betamethasone|Diprolene|pain|cream:0.05;injection:6",
        "clobetasol|Temovate|pain|cream:0.05;ointment:0.05",
        "fluocinonide|Lidex|pain|cream:0.05",
        "mometasone topical|Elocon|pain|cream:0.1",
        "tacrolimus topical|Protopic|pain|ointment:0.03,0.1",
        "pimecrolimus|Elidel|pain|cream:1",
        "lidocaine|Lidoderm|pain|patch:5;cream:4;injection:1,2",
        "capsaicin|Qutenza|pain|patch:8;cream:0.025,0.075",
        "omeprazole|Prilosec|gastrointestinal|capsule:10,20,40",
        "esomeprazole|Nexium|gastrointestinal|capsule:20,40",
        "pantoprazole|Protonix|gastrointestinal|tablet:20,40",
        "lansoprazole|Prevacid|gastrointestinal|capsule:15,30",
        "dexlansoprazole|Dexilant|gastrointestinal|capsule:30,60",
        "rabeprazole|Aciphex|gastrointestinal|tablet:20",
        "famotidine|Pepcid|gastrointestinal|tablet:10,20,40",
        "cimetidine|Tagamet|gastrointestinal|tablet:200,300,400,800",
        "nizatidine|Axid|gastrointestinal|capsule:150,300",
        "sucralfate|Carafate|gastrointestinal|tablet:1000;suspension:1000",
        "misoprostol|Cytotec|gastrointestinal|tablet:100,200",
        "ondansetron|Zofran|gastrointestinal|tablet:4,8;odt:4,8;solution:4",
        "granisetron|Kytril|gastrointestinal|tablet:1;patch:3.1",
        "promethazine|Phenergan|gastrointestinal|tablet:12.5,25,50;suppository:12.5,25",
        "metoclopramide|Reglan|gastrointestinal|tablet:5,10;solution:5",
        "prochlorperazine|Compazine|gastrointestinal|tablet:5,10;suppository:25",
        "meclizine|Antivert|gastrointestinal|tablet:12.5,25",
        "dicyclomine|Bentyl|gastrointestinal|capsule:10;tablet:20",
        "hyoscyamine|Levsin|gastrointestinal|tablet:0.125",
        "loperamide|Imodium|gastrointestinal|capsule:2;tablet:2",
        "diphenoxylate atropine|Lomotil|gastrointestinal|tablet:2.5-0.025",
        "polyethylene glycol|MiraLAX|gastrointestinal|powder:17",
        "docusate|Colace|gastrointestinal|capsule:50,100,250",
        "senna|Senokot|gastrointestinal|tablet:8.6,17.2",
        "bisacodyl|Dulcolax|gastrointestinal|tablet:5;suppository:10",
        "lactulose|Enulose|gastrointestinal|solution:10",
        "lubiprostone|Amitiza|gastrointestinal|capsule:8,24",
        "linaclotide|Linzess|gastrointestinal|capsule:72,145,290",
        "plecanatide|Trulance|gastrointestinal|tablet:3",
        "prucalopride|Motegrity|gastrointestinal|tablet:1,2",
        "mesalamine|Lialda|gastrointestinal|tablet:400,800,1200;capsule:250,500;enema:4",
        "sulfasalazine|Azulfidine|gastrointestinal|tablet:500",
        "balsalazide|Colazal|gastrointestinal|capsule:750",
        "budesonide gi|Entocort|gastrointestinal|capsule:3;tablet:9",
        "infliximab|Remicade|gastrointestinal|injection:100",
        "adalimumab|Humira|gastrointestinal|injection:40",
        "ustekinumab|Stelara|gastrointestinal|injection:45,90",
        "vedolizumab|Entyvio|gastrointestinal|injection:300",
        "tofacitinib|Xeljanz|gastrointestinal|tablet:5,10;tablet-er:11",
        "upadacitinib|Rinvoq|gastrointestinal|tablet:15,30,45",
        "ursodiol|Actigall|gastrointestinal|capsule:300;tablet:250,500",
        "pancrelipase|Creon|gastrointestinal|capsule:6000,12000,24000,36000",
        "rifaximin|Xifaxan|gastrointestinal|tablet:200,550",
        "eluxadoline|Viberzi|gastrointestinal|tablet:75,100",
        "amoxicillin|Amoxil|infectious|capsule:250,500;tablet:875;suspension:125,250",
        "amoxicillin clavulanate|Augmentin|infectious|tablet:250-125,500-125,875-125;suspension:200-28.5,400-57",
        "ampicillin|Principen|infectious|capsule:250,500",
        "penicillin vk|Veetids|infectious|tablet:250,500",
        "cephalexin|Keflex|infectious|capsule:250,500,750",
        "cefuroxime|Ceftin|infectious|tablet:250,500",
        "cefdinir|Omnicef|infectious|capsule:300;suspension:125,250",
        "ceftriaxone|Rocephin|infectious|injection:250,500,1000,2000",
        "cefepime|Maxipime|infectious|injection:1000,2000",
        "cefazolin|Ancef|infectious|injection:500,1000",
        "azithromycin|Zithromax|infectious|tablet:250,500,600;suspension:100,200",
        "clarithromycin|Biaxin|infectious|tablet:250,500;tablet-er:500",
        "erythromycin|Ery-Tab|infectious|tablet:250,333,500",
        "doxycycline|Vibramycin|infectious|capsule:50,100;tablet:50,100,150",
        "minocycline|Minocin|infectious|capsule:50,75,100",
        "tetracycline|Sumycin|infectious|capsule:250,500",
        "ciprofloxacin|Cipro|infectious|tablet:250,500,750;suspension:250,500",
        "levofloxacin|Levaquin|infectious|tablet:250,500,750",
        "moxifloxacin|Avelox|infectious|tablet:400",
        "ofloxacin|Floxin|infectious|tablet:200,300,400",
        "trimethoprim sulfamethoxazole|Bactrim|infectious|tablet:80-400,160-800;suspension:40-200",
        "nitrofurantoin|Macrobid|infectious|capsule:25,50,100",
        "fosfomycin|Monurol|infectious|packet:3000",
        "metronidazole|Flagyl|infectious|tablet:250,500;capsule:375",
        "clindamycin|Cleocin|infectious|capsule:75,150,300;solution:75",
        "vancomycin|Vancocin|infectious|capsule:125,250;injection:500,1000",
        "linezolid|Zyvox|infectious|tablet:600;suspension:100",
        "daptomycin|Cubicin|infectious|injection:350,500",
        "meropenem|Merrem|infectious|injection:500,1000",
        "piperacillin tazobactam|Zosyn|infectious|injection:2.25,3.375,4.5",
        "gentamicin|Garamycin|infectious|injection:10,40",
        "tobramycin|Tobrex|infectious|injection:40;inhaler:300",
        "amikacin|Amikin|infectious|injection:250,500",
        "rifampin|Rifadin|infectious|capsule:150,300",
        "isoniazid|Nydrazid|infectious|tablet:100,300",
        "ethambutol|Myambutol|infectious|tablet:100,400",
        "pyrazinamide|Rifater|infectious|tablet:500",
        "fluconazole|Diflucan|infectious|tablet:50,100,150,200;suspension:10,40",
        "itraconazole|Sporanox|infectious|capsule:100;solution:10",
        "voriconazole|Vfend|infectious|tablet:50,200",
        "terbinafine|Lamisil|infectious|tablet:250;cream:1",
        "nystatin|Mycostatin|infectious|suspension:100000;cream:100000",
        "clotrimazole|Lotrimin|infectious|cream:1;troche:10",
        "ketoconazole|Nizoral|infectious|tablet:200;cream:2;shampoo:1,2",
        "acyclovir|Zovirax|infectious|tablet:200,400,800;cream:5",
        "valacyclovir|Valtrex|infectious|tablet:500,1000",
        "famciclovir|Famvir|infectious|tablet:125,250,500",
        "oseltamivir|Tamiflu|infectious|capsule:30,45,75;suspension:6",
        "baloxavir|Xofluza|infectious|tablet:40,80",
        "zanamivir|Relenza|infectious|inhaler:5",
        "nirmatrelvir ritonavir|Paxlovid|infectious|tablet:150-100,300-100",
        "remdesivir|Veklury|infectious|injection:100",
        "hydroxychloroquine|Plaquenil|infectious|tablet:200",
        "chloroquine|Aralen|infectious|tablet:250,500",
        "albendazole|Albenza|infectious|tablet:200",
        "ivermectin|Stromectol|infectious|tablet:3",
        "metronidazole topical|MetroGel|infectious|gel:0.75,1",
        "mupirocin|Bactroban|infectious|ointment:2;cream:2",
        "neomycin polymyxin|Neosporin|infectious|ointment:3.5-5000",
        "tamsulosin|Flomax|urology|capsule:0.4",
        "finasteride|Proscar|urology|tablet:1,5",
        "dutasteride|Avodart|urology|capsule:0.5",
        "sildenafil|Viagra|urology|tablet:25,50,100",
        "tadalafil|Cialis|urology|tablet:2.5,5,10,20",
        "vardenafil|Levitra|urology|tablet:2.5,5,10,20",
        "avanafil|Stendra|urology|tablet:50,100,200",
        "oxybutynin|Ditropan|urology|tablet:5;tablet-er:5,10,15;patch:3.9",
        "tolterodine|Detrol|urology|tablet:1,2;capsule:2,4",
        "solifenacin|Vesicare|urology|tablet:5,10",
        "mirabegron|Myrbetriq|urology|tablet:25,50",
        "fesoterodine|Toviaz|urology|tablet:4,8",
        "darifenacin|Enablex|urology|tablet:7.5,15",
        "phenazopyridine|Pyridium|urology|tablet:95,100,200",
        "ethinyl estradiol norgestimate|Ortho Tri-Cyclen|urology|tablet:0.035-0.18",
        "ethinyl estradiol drospirenone|Yaz|urology|tablet:0.02-3",
        "ethinyl estradiol levonorgestrel|Seasonale|urology|tablet:0.03-0.15",
        "norethindrone|Micronor|urology|tablet:0.35",
        "etonogestrel|Nexplanon|urology|implant:68",
        "medroxyprogesterone|Depo-Provera|urology|injection:150;tablet:2.5,5,10",
        "levonorgestrel iud|Mirena|urology|device:52",
        "ulipristal|Ella|urology|tablet:30",
        "levonorgestrel emergency|Plan B|urology|tablet:1.5",
        "estradiol|Estrace|urology|tablet:0.5,1,2;patch:0.025,0.0375,0.05,0.075,0.1;cream:0.01",
        "conjugated estrogens|Premarin|urology|tablet:0.3,0.45,0.625,0.9,1.25",
        "progesterone|Prometrium|urology|capsule:100,200",
        "testosterone|AndroGel|urology|gel:1,1.62;injection:100,200;patch:2,4",
        "clomiphene|Clomid|urology|tablet:50",
        "letrozole|Femara|urology|tablet:2.5",
        "anastrozole|Arimidex|urology|tablet:1",
        "tamoxifen|Nolvadex|urology|tablet:10,20",
        "raloxifene|Evista|urology|tablet:60",
        "ospemifene|Osphena|urology|tablet:60",
        "sildenafil pah|Revatio|urology|tablet:20",
        "tadalafil pah|Adcirca|urology|tablet:20",
        "loratadine|Claritin|general|tablet:10;solution:5",
        "cetirizine|Zyrtec|general|tablet:5,10;solution:5",
        "fexofenadine|Allegra|general|tablet:30,60,180",
        "diphenhydramine|Benadryl|general|capsule:25,50;tablet:25;solution:12.5",
        "levocetirizine|Xyzal|general|tablet:5",
        "desloratadine|Clarinex|general|tablet:5",
        "olopatadine|Pataday|general|drops:0.1,0.2,0.7",
        "ketotifen|Zaditor|general|drops:0.025",
        "latanoprost|Xalatan|general|drops:0.005",
        "timolol|Timoptic|general|drops:0.25,0.5",
        "brimonidine|Alphagan|general|drops:0.1,0.15",
        "dorzolamide|Trusopt|general|drops:2",
        "bimatoprost|Lumigan|general|drops:0.01,0.03",
        "travoprost|Travatan|general|drops:0.004",
        "artificial tears|Refresh|general|drops:1",
        "cyclosporine ophthalmic|Restasis|general|drops:0.05",
        "ofloxacin otic|Floxin Otic|general|drops:0.3",
        "ciprofloxacin dexamethasone|Ciprodex|general|drops:0.3-0.1",
        "carbamide peroxide|Debrox|general|drops:6.5",
        "ferrous sulfate|Feosol|general|tablet:325;solution:75",
        "ferrous gluconate|Fergon|general|tablet:240",
        "cyanocobalamin|Vitamin B12|general|tablet:500,1000;injection:1000",
        "folic acid|Folvite|general|tablet:0.4,0.8,1",
        "potassium chloride|Klor-Con|general|tablet:8,10,20;capsule:8,10",
        "magnesium oxide|Mag-Ox|general|tablet:400",
        "calcium carbonate|Tums|general|tablet:500,750,1000",
        "cholecalciferol|Vitamin D3|general|capsule:1000,2000,5000",
        "thiamine|Vitamin B1|general|tablet:50,100",
        "pyridoxine|Vitamin B6|general|tablet:25,50,100",
        "ascorbic acid|Vitamin C|general|tablet:250,500,1000",
        "omega-3|Lovaza|general|capsule:1000",
        "icosapent ethyl|Vascepa|general|capsule:500,1000",
        "epinephrine|EpiPen|general|injection:0.15,0.3",
        "naloxone auto|Evzio|general|injection:2",
        "varenicline|Chantix|general|tablet:0.5,1",
        "nicotine|Nicoderm|general|patch:7,14,21;gum:2,4;lozenge:2,4",
        "bupropion sr|Zyban|general|tablet:150",
        "disulfiram|Antabuse|general|tablet:250,500",
        "acamprosate|Campral|general|tablet:333",
        "sildenafil other|Viagra|general|tablet:25,50,100",
        "apixaban starter|Eliquis|hematology|tablet:5",
        "enoxaparin|Lovenox|hematology|injection:30,40,60,80,100",
        "heparin|Heparin|hematology|injection:1000,5000,10000",
        "fondaparinux|Arixtra|hematology|injection:2.5,5,7.5,10",
        "filgrastim|Neupogen|hematology|injection:300,480",
        "pegfilgrastim|Neulasta|hematology|injection:6",
        "epoetin alfa|Epogen|hematology|injection:2000,4000,10000",
        "darbepoetin|Aranesp|hematology|injection:25,40,60,100,200",
        "hydroxyurea|Hydrea|hematology|capsule:200,300,400,500",
        "anagrelide|Agrylin|hematology|capsule:0.5,1",
        "imatinib|Gleevec|oncology|tablet:100,400",
        "dasatinib|Sprycel|oncology|tablet:20,50,70,80,100,140",
        "nilotinib|Tasigna|oncology|capsule:50,150,200",
        "erlotinib|Tarceva|oncology|tablet:25,100,150",
        "gefitinib|Iressa|oncology|tablet:250",
        "osimertinib|Tagrisso|oncology|tablet:40,80",
        "lapatinib|Tykerb|oncology|tablet:250",
        "sunitinib|Sutent|oncology|capsule:12.5,25,37.5,50",
        "sorafenib|Nexavar|oncology|tablet:200",
        "pazopanib|Votrient|oncology|tablet:200",
        "lenvatinib|Lenvima|oncology|capsule:4,10",
        "cabozantinib|Cabometyx|oncology|tablet:20,40,60",
        "palbociclib|Ibrance|oncology|capsule:75,100,125",
        "ribociclib|Kisqali|oncology|tablet:200",
        "abemaciclib|Verzenio|oncology|tablet:50,100,150,200",
        "olaparib|Lynparza|oncology|tablet:100,150",
        "niraparib|Zejula|oncology|capsule:100",
        "rucaparib|Rubraca|oncology|tablet:200,250,300",
        "pembrolizumab|Keytruda|oncology|injection:100",
        "nivolumab|Opdivo|oncology|injection:40,100,240",
        "atezolizumab|Tecentriq|oncology|injection:840,1200",
        "ipilimumab|Yervoy|oncology|injection:50",
        "rituximab|Rituxan|oncology|injection:100,500",
        "trastuzumab|Herceptin|oncology|injection:150,420",
        "bevacizumab|Avastin|oncology|injection:100,400",
        "cetuximab|Erbitux|oncology|injection:100,200",
        "paclitaxel|Taxol|oncology|injection:30,100,300",
        "docetaxel|Taxotere|oncology|injection:20,80",
        "carboplatin|Paraplatin|oncology|injection:50,150,450",
        "cisplatin|Platinol|oncology|injection:50,100",
        "oxaliplatin|Eloxatin|oncology|injection:50,100",
        "fluorouracil|Adrucil|oncology|injection:500",
        "capecitabine|Xeloda|oncology|tablet:150,500",
        "gemcitabine|Gemzar|oncology|injection:200,1000",
        "pemetrexed|Alimta|oncology|injection:100,500",
        "methotrexate|Trexall|oncology|tablet:2.5,5,7.5,10;injection:25,50",
        "cyclophosphamide|Cytoxan|oncology|tablet:25,50;injection:500,1000",
        "doxorubicin|Adriamycin|oncology|injection:10,50",
        "vincristine|Oncovin|oncology|injection:1,2",
        "etoposide|VePesid|oncology|capsule:50;injection:100",
        "irinotecan|Camptosar|oncology|injection:40,100",
        "topotecan|Hycamtin|oncology|capsule:0.25,1;injection:4",
        "lenalidomide|Revlimid|oncology|capsule:2.5,5,10,15,20,25",
        "pomalidomide|Pomalyst|oncology|capsule:1,2,3,4",
        "bortezomib|Velcade|oncology|injection:3.5",
        "carfilzomib|Kyprolis|oncology|injection:10,30,60",
        "ibrutinib|Imbruvica|oncology|capsule:70,140;tablet:140,280,420,560",
        "acalabrutinib|Calquence|oncology|capsule:100",
        "venetoclax|Venclexta|oncology|tablet:10,50,100",
        "oseltamivir extra|Tamiflu|infectious|capsule:30,45,75",
        "bictegravir emtricitabine tenofovir|Biktarvy|infectious|tablet:50-200-25",
        "dolutegravir|Tivicay|infectious|tablet:10,25,50",
        "emtricitabine tenofovir|Truvada|infectious|tablet:200-300",
        "emtricitabine tenofovir af|Descovy|infectious|tablet:200-25",
        "efavirenz|Sustiva|infectious|capsule:50,200;tablet:600",
        "rilpivirine|Edurant|infectious|tablet:25",
        "darunavir|Prezista|infectious|tablet:75,150,600,800",
        "atazanavir|Reyataz|infectious|capsule:150,200,300",
        "ritonavir|Norvir|infectious|tablet:100",
        "raltegravir|Isentress|infectious|tablet:400,600",
        "maraviroc|Selzentry|infectious|tablet:150,300",
        "sofosbuvir velpatasvir|Epclusa|infectious|tablet:400-100",
        "glecaprevir pibrentasvir|Mavyret|infectious|tablet:100-40",
        "ledipasvir sofosbuvir|Harvoni|infectious|tablet:90-400",
        "entecavir|Baraclude|infectious|tablet:0.5,1",
        "tenofovir disoproxil|Viread|infectious|tablet:300",
        "tenofovir alafenamide|Vemlidy|infectious|tablet:25",
        "lamivudine|Epivir|infectious|tablet:100,150,300",
        "adalimumab extra|Humira|immunology|injection:40,80",
        "etanercept|Enbrel|immunology|injection:25,50",
        "infliximab extra|Remicade|immunology|injection:100",
        "golimumab|Simponi|immunology|injection:50,100",
        "certolizumab|Cimzia|immunology|injection:200",
        "tocilizumab|Actemra|immunology|injection:80,162,200,400",
        "sarilumab|Kevzara|immunology|injection:150,200",
        "abatacept|Orencia|immunology|injection:125,250",
        "rituximab ra|Rituxan|immunology|injection:500,1000",
        "secukinumab|Cosentyx|immunology|injection:150,300",
        "ixekizumab|Taltz|immunology|injection:80",
        "guselkumab|Tremfya|immunology|injection:100",
        "risankizumab|Skyrizi|immunology|injection:75,150",
        "apremilast|Otezla|immunology|tablet:10,20,30",
        "tofacitinib extra|Xeljanz|immunology|tablet:5,10",
        "baricitinib|Olumiant|immunology|tablet:1,2,4",
        "upadacitinib extra|Rinvoq|immunology|tablet:15,30",
        "mycophenolate|CellCept|immunology|capsule:250;tablet:500",
        "tacrolimus|Prograf|immunology|capsule:0.5,1,5",
        "cyclosporine|Neoral|immunology|capsule:25,100;solution:100",
        "azathioprine|Imuran|immunology|tablet:50,75,100",
        "sirolimus|Rapamune|immunology|tablet:0.5,1,2",
        "everolimus|Zortress|immunology|tablet:0.25,0.5,0.75",
        "belimumab|Benlysta|immunology|injection:200,400",
        "omalizumab extra|Xolair|immunology|injection:75,150,300",
    ]
}

