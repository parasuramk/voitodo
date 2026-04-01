import Foundation
import NaturalLanguage

class AIService {
    static let shared = AIService()
    
    private init() {}
    
    /// Cleans up a rambling raw transcript into a single, actionable sentence.
    /// In the future (V1.3+), this will hook into Apple Intelligence Foundation Models.
    func summarize(transcript: String) async -> String {
        // V1.1 English NLP-based fast cleanup (On-device)
        let words = transcript.split(separator: " ").map { String($0) }
        
        // Common verbal fillers to remove
        let fillers: Set<String> = ["um", "uh", "like", "you know", "i mean", "so basically", "basically"]
        
        let filteredWords = words.filter { word in
            let cleanWord = word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return !fillers.contains(cleanWord)
        }
        
        var cleanText = filteredWords.joined(separator: " ")
        
        if let first = cleanText.first {
            cleanText = String(first).uppercased() + cleanText.dropFirst()
        }
        
        if !cleanText.hasSuffix(".") && !cleanText.hasSuffix("!") && !cleanText.hasSuffix("?") && !cleanText.isEmpty {
            cleanText += "."
        }
        
        // If it was completely filtered out, just return the original transcript
        return cleanText.isEmpty ? transcript : cleanText
    }
    
    // MARK: - Intent Brokerage

    /// Strong purchase verbs — always win over negation words (fix, repair)
    private lazy var strongIntentKeywords: [String] = {
        loadIntentTier("strong")
    }()

    /// Context/weak intent — occasion words and softer verbs that yield to negation
    private lazy var contextIntentKeywords: [String] = {
        loadIntentTier("context")
    }()

    /// Repair/maintenance verbs that suppress the Shop action — unless a strong intent also exists
    private lazy var negationKeywords: [String] = {
        loadStringArray(from: "negation_keywords")
    }()

    /// Lazily loaded from product_keywords.json (categorized) — flattened, sorted by length descending, cached in memory
    private lazy var productKeywords: [String] = {
        guard let url = Bundle.main.url(forResource: "product_keywords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [] }
        return dict.values.flatMap { $0 }.sorted(by: { $0.count > $1.count })
    }()

    /// Short keywords that need word-boundary regex matching to avoid false positives
    /// e.g. "ac" inside "headache", "tv" inside "activity"
    private let boundaryMatchedKeywords: Set<String> = [
        "ac", "tv", "bus", "cab", "ola", "ssd", "fan", "bag", "tea", "oil", "dal"
    ]

    private func loadStringArray(from filename: String) -> [String] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let array = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return array
    }

    private func loadIntentTier(_ tier: String) -> [String] {
        guard let url = Bundle.main.url(forResource: "intent_keywords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [] }
        return dict[tier] ?? []
    }

    /// Detects commercial intent using a 3-tier priority engine:
    ///   Tier 1 (Strong Intent): buy/order/purchase — always shows the Shop action.
    ///   Tier 1 (Context Intent): need/get/birthday — shows Shop action UNLESS a negation verb is also present.
    ///   Negation Override: fix/repair/service — suppresses Shop action, but yields to strong intent.
    ///   Tier 2 (Product Scan): verifies a known product noun exists in the thought.
    func detectShoppingIntent(in text: String) -> (isShopping: Bool, query: String?) {
        let textLower = text.lowercased()

        let hasStrongIntent  = strongIntentKeywords.contains  { textLower.contains($0) }
        let hasContextIntent = contextIntentKeywords.contains { textLower.contains($0) }
        let hasNegation      = negationKeywords.contains      { textLower.contains($0) }

        // Decision logic (Option 4 — positive priority):
        // • Strong intent present → proceed regardless of negation
        // • Negation present WITHOUT strong intent → suppress
        // • Context intent only → proceed (no negation present)
        // • No intent at all → suppress
        let shouldProceed: Bool
        if hasStrongIntent {
            shouldProceed = true                        // "buy a new fan" → SHOP even if "fix" also present
        } else if hasNegation {
            shouldProceed = false                       // "fix the fan" → SKIP
        } else {
            shouldProceed = hasContextIntent            // "need a fan" → SHOP; no intent → SKIP
        }

        if !shouldProceed { return (false, nil) }

        // Tier 2: Product scan
        var foundProducts: [String] = []
        var searchString = textLower

        for product in productKeywords {
            let matched: Bool
            if boundaryMatchedKeywords.contains(product) {
                let pattern = "(?<![a-z0-9])\(NSRegularExpression.escapedPattern(for: product))(?![a-z0-9])"
                matched = (try? NSRegularExpression(pattern: pattern))?.firstMatch(
                    in: searchString, range: NSRange(searchString.startIndex..., in: searchString)
                ) != nil
            } else {
                matched = searchString.contains(product)
            }

            if matched {
                foundProducts.append(product)
                searchString = searchString.replacingOccurrences(of: product, with: "")
            }
        }

        if foundProducts.isEmpty { return (false, nil) }
        return (true, foundProducts.joined(separator: " "))
    }
}
