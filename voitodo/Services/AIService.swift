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
            // Fashion & Footwear
            "running shoes", "sports shoes", "formal shoes", "ethnic wear", "formal shirt",
            "anniversary gift", "birthday gift", "diwali gift",
            "shoes", "sneakers", "sandals", "slippers", "boots",
            "shirt", "t-shirt", "jeans", "trousers", "kurta", "saree", "salwar",
            "watch", "belt", "wallet", "bag", "backpack", "handbag",

            // Electronics & Accessories
            "bluetooth speaker", "washing machine", "power bank", "hard disk", "phone charger",
            "phone", "smartphone", "charger", "earphones", "headphones",
            "laptop", "tablet", "mouse", "keyboard", "pendrive", "ssd",
            "fan", "cooler", "ac", "refrigerator", "microwave", "tv",

            // Daily Essentials & Groceries
            "cleaning products", "toothpaste",
            "milk", "bread", "eggs", "rice", "dal", "atta", "oil", "sugar", "tea", "coffee",
            "vegetables", "fruits", "spices", "masala", "snacks", "biscuits", "chocolate",
            "soap", "shampoo", "detergent",

            // Health & Personal Care
            "protein powder", "whey protein", "face wash", "moisturizer",
            "medicine", "syrup", "ointment", "cream", "vitamins", "supplements",

            // Home & Kitchen
            "extension board", "mattress", "bedsheet", "curtain", "furniture",
            "chair", "table", "pillow", "bulb", "switch", "plug", "wire", "inverter",

            // Beauty & Personal Care
            "hair oil", "perfume", "deodorant", "lipstick", "makeup", "comb", "trimmer",

            // Travel & Booking
            "flight", "train", "hotel", "ticket", "booking", "bus", "cab", "ola", "uber",

            // Gifts & Occasion
            "gift", "present"
        ].sorted(by: { $0.count > $1.count })
        
        var foundProducts: [String] = []
        var searchString = textLower
        
        for product in productKeywords {
            // Use word-boundary matching for very short keywords to prevent
            // sub-string false positives (e.g. "ac" inside "headache", "tv" inside "activity")
            let shortKeywords: Set<String> = ["ac", "tv", "bus", "cab", "ola", "ssd", "fan", "bag", "tea", "oil", "dal"]
            let matched: Bool
            if shortKeywords.contains(product) {
                // Check that the keyword is surrounded by non-alphanumeric characters
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
