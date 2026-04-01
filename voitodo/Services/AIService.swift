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
        
        let triggers = [
            "need to buy", "want to buy", "looking to buy", "going to buy",
            "want to order", "need to order", 
            "need to get", "want to get", "have to get",
            "looking for a", "looking for", 
            "need new", "get a new", "buy a new", "buy new", 
            "shop for", "order some", "buy some", "get some", "get groceries",
            "purchase", "buy", "order"
        ]
        
        var queryRaw = ""
        var found = false
        
        for trigger in triggers {
            if let range = textLower.range(of: trigger) {
                queryRaw = String(text[range.upperBound...])
                found = true
                break
            }
        }
        
        if !found { return (false, nil) }
        
        var finalQuery = queryRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Boundaries to split extra clauses or descriptors that break Amazon search
        let clauseBoundaries = [
            ", the ", ", my ", ", it ", " because ", " so ", " but ", " for ", " on ", " at "
        ]
        
        for boundary in clauseBoundaries {
            if let range = finalQuery.lowercased().range(of: boundary) {
                finalQuery = String(finalQuery[..<range.lowerBound])
            }
        }
        
        // Clean prefixes that dilute the actual noun
        finalQuery = finalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if finalQuery.lowercased().hasPrefix("a ") { finalQuery.removeFirst(2) }
        if finalQuery.lowercased().hasPrefix("some ") { finalQuery.removeFirst(5) }
        
        finalQuery = finalQuery.trimmingCharacters(in: .whitespaces)
        
        // Clean trailing punctuation
        while finalQuery.hasSuffix(".") || finalQuery.hasSuffix(",") || finalQuery.hasSuffix("-") {
            finalQuery.removeLast()
            finalQuery = finalQuery.trimmingCharacters(in: .whitespaces)
        }
        
        if finalQuery.isEmpty { return (false, nil) }
        
        return (true, finalQuery)
    }
}
