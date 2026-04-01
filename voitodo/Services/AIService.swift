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
    
    /// Detects commercial intent and extracts the purchase item (e.g., "buy an ergonomic chair" -> "an ergonomic chair")
    func detectShoppingIntent(in text: String) -> (isShopping: Bool, query: String?) {
        let textLower = text.lowercased()
        let shoppingVerbs = ["buy", "order", "purchase", "get a new", "shop for"]
        
        for verb in shoppingVerbs {
            if let range = textLower.range(of: verb) {
                let queryRaw = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: .punctuationCharacters)
                
                let stopWords = [" from", " on", " at", " because", " so", " tomorrow", " for"]
                var finalQuery = queryRaw
                for stop in stopWords {
                    if let stopRange = finalQuery.lowercased().range(of: stop) {
                        finalQuery = String(finalQuery[..<stopRange.lowerBound])
                    }
                }
                
                if !finalQuery.isEmpty {
                    return (true, finalQuery.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        return (false, nil)
    }
}
