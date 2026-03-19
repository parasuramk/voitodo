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
}
