import Foundation

/// Turn a message into a topic query that is safe to send off the phone.
///
/// Swift twin of `backend/scout/privacy.py` — Scout runs the same rules again
/// on arrival. What survives is a bag of topic keywords: no names (the user's
/// or anyone they support), no numbers (ages, hours, vitals, doses), no
/// contact details, no first-person narrative.
///
/// "I'm 34, slept 5 hours, my wife Priya says my resting HR of 71 is high —
/// should I skip leg day?" leaves as `resting hr high skip leg day`.
public enum AriaQueryPrivacy {

    public static let maxKeywords = 10

    /// Health / training terms that legitimately carry digits.
    static let digitTerms: Set<String> = [
        "vo2", "vo2max", "omega-3", "omega3", "b12", "b6", "d3", "k2",
        "5k", "10k", "pm2.5", "covid-19", "zone-2", "zone2", "5x5", "a1c",
    ]

    static let stopwords: Set<String> = Set("""
    a an and are as at be been being but by can could did do does doing done
    for from had has have having he her hers him his how i i'd i'll i'm i've
    if in into is it it's its just me mine my myself of on or our ours she
    should so than that that's the their them then there these they this
    those to too up us was we we're were what what's when where which while
    who whom why will with would you you're your yours yourself am im ive
    id ill dont don't doesnt doesn't cant can't wont won't isnt isn't
    really very much many some any also still ok okay please thanks thank
    hey hi hello aria yeah yes no not today tonight tomorrow yesterday
    morning evening night week weekend
    wife husband partner girlfriend boyfriend son daughter mom dad mother
    father brother sister friend boss coworker kid kids baby
    named called says said told tell name
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))

    private static let removals: [NSRegularExpression] = [
        #"\b[\w.+-]+@[\w-]+\.[\w.-]+\b"#,                          // email
        #"\bhttps?://\S+|\bwww\.\S+"#,                              // url
        #"\+?\d[\d\s().-]{6,}\d"#,                                  // phone
        #"(?<!\w)@\w+"#,                                            // handle
        #"\b(?:named|called|name\s+is|name's|this\s+is)\s+\S+"#,    // "my name is Lee"
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let token = try? NSRegularExpression(
        pattern: #"[a-z][a-z0-9.+'-]*|\d[a-z0-9.+'-]*"#,
        options: [.caseInsensitive]
    )

    public static func scrub(_ text: String, privateTerms: [String] = []) -> String {
        var raw = text
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        for re in removals {
            raw = re.stringByReplacingMatches(
                in: raw,
                range: NSRange(raw.startIndex..<raw.endIndex, in: raw),
                withTemplate: " "
            )
        }
        let privateWords: Set<String> = Set(
            privateTerms
                .flatMap { $0.lowercased().split(separator: " ").map(String.init) }
                .filter { $0.count >= 2 }
        )
        let lower = raw.lowercased()
        guard let token else { return "" }
        var keywords: [String] = []
        let ns = lower as NSString
        for match in token.matches(in: lower, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: match.range)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".'+-"))
            guard word.count >= 2,
                  !stopwords.contains(word),
                  !privateWords.contains(word) else { continue }
            if word.contains(where: \.isNumber), !digitTerms.contains(word) { continue }
            if !keywords.contains(word) { keywords.append(word) }
            if keywords.count >= maxKeywords { break }
        }
        return keywords.joined(separator: " ")
    }
}
