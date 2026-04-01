import Foundation

let trackingID = "whatodo0f-21"

func generateAmazonIndiaURL(for query: String) -> URL? {
    let baseURL = "https://www.amazon.in/s"
    var components = URLComponents(string: baseURL)
    
    components?.queryItems = [
        URLQueryItem(name: "k", value: query),
        URLQueryItem(name: "tag", value: trackingID)
    ]
    
    return components?.url
}

print(generateAmazonIndiaURL(for: "running shoes")?.absoluteString ?? "NIL")
