import Foundation

class AffiliateService {
    static let shared = AffiliateService()
    
    // The Tracking ID provided by the user
    private let trackingID = "whatodo0f-21"
    
    // Validates whether the device is configured for India
    func isIndiaRegion() -> Bool {
        if #available(iOS 16, *) {
            return Locale.current.region?.identifier == "IN"
        } else {
            return Locale.current.regionCode == "IN" // Fallback
        }
    }
    
    // Checks both user opt-in prefix and system region
    func canShowAffiliateLinks() -> Bool {
        let isEnabled = UserDefaults.standard.bool(forKey: "isShoppingSuggestionsEnabled")
        return isEnabled && isIndiaRegion()
    }
    
    // Generates the Amazon.in search URL using the tracking ID
    func generateAmazonIndiaURL(for query: String) -> URL? {
        let baseURL = "https://www.amazon.in/s"
        var components = URLComponents(string: baseURL)
        
        components?.queryItems = [
            URLQueryItem(name: "k", value: query),
            URLQueryItem(name: "tag", value: trackingID)
        ]
        
        return components?.url
    }
}
