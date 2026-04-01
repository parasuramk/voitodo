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
    
    /// Detects commercial intent and extracts the purchase item (e.g., "buy an ergonomic chair" -> "chair")
    /// Uses a primary list to detect intent and a secondary dictionary to extract the verified product noun.
    func detectShoppingIntent(in text: String) -> (isShopping: Bool, query: String?) {
        let textLower = text.lowercased()
        
        let intentKeywords = [
            "buy", "order", "purchase", "get", "looking for", "shop for", "find", "need"
        ]
        
        var hasIntent = false
        for intent in intentKeywords {
            if textLower.contains(intent) {
                hasIntent = true
                break
            }
        }
        
        if !hasIntent { return (false, nil) }
        
        // Define the verified product dictionary. 
        // We sort by length descending to prioritize multi-word matches ("running shoes") over singles ("shoes").
        let productKeywords = [
            "running shoes", "shoes", "milk", "eggs", "bread", 
            "phone charger", "charger", "groceries", "rice", "dal", "vegetables", "oil",
            "laptop", "gift", "watch", "perfume", "formal shirts", "shirts", "t-shirts", 
            "medicines", "headset"
        ].sorted(by: { $0.count > $1.count })
        
        var foundProducts: [String] = []
        var searchString = textLower 
        
        for product in productKeywords {
            if searchString.contains(product) {
                foundProducts.append(product)
                // Mask the matched substring to avoid sub-matches (e.g., matching "shoes" after "running shoes")
                searchString = searchString.replacingOccurrences(of: product, with: "")
            }
        }
        
        if foundProducts.isEmpty {
            return (false, nil)
        }
        
        return (true, foundProducts.joined(separator: " "))
    }
}
