import Foundation

func detectShoppingIntent(in text: String) -> (isShopping: Bool, query: String?) {
    let textLower = text.lowercased()
    
    // 1. Primary Intent List
    let intentKeywords = [
        "buy", "order", "purchase", "get", "looking for", "shop for", "find", "need"
    ]
    
    var hasIntent = false
    for intent in intentKeywords {
        // Use regex or word boundaries to prevent "buying" from matching "buy"?
        // lowercased contains is fine for MVP.
        if textLower.contains(intent) {
            hasIntent = true
            break
        }
    }
    
    if !hasIntent { return (false, nil) }
    
    // 2. Secondary Product Dictionary (Sorted by length descending to prevent partial match e.g. "phone charger" vs "charger")
    let productKeywords = [
        "running shoes", "shoes", "milk", "eggs", "bread", 
        "phone charger", "charger", "groceries", "rice", "dal", "vegetables", "oil",
        "laptop", "gift", "watch", "perfume", "formal shirts", "shirts", "t-shirts", 
        "medicines", "headset"
    ].sorted(by: { $0.count > $1.count })
    
    // Find ALL matching products to support lists like "milk, eggs and bread"
    var foundProducts: [String] = []
    
    var searchString = textLower // mutated to prevent overlapping matches
    
    for product in productKeywords {
        if let range = searchString.range(of: product) {
            foundProducts.append(product)
            // Mask out the found product so we don't double count "shoes" inside "running shoes"
            // Wait, we sorted by length, so "running shoes" matches first. Then "shoes" won't match if we remove "running shoes".
            searchString = searchString.replacingOccurrences(of: product, with: "")
        }
    }
    
    if foundProducts.isEmpty {
        return (false, nil)
    }
    
    // Join the exact dictionary matches (e.g. "milk eggs bread")
    // Note: They won't be in original sentence order, they'll be in length order, but Amazon doesn't care.
    let amazonQuery = foundProducts.joined(separator: " ")
    return (true, amazonQuery)
}

let tests = [
    "I need to buy new running shoes for morning walk",
    "Buy some milk, eggs and bread on the way home",
    "Want to order a new phone charger, the old one is broken",
    "Need to get groceries - rice, dal, vegetables and oil",
    "Looking for a good laptop under 50k for my son",
    "Buy a gift for Shruti’s birthday, maybe a watch or perfume",
    "I need new formal shirts for office",
    "Order some medicines for headache and fever",
    "Find a good headset"
]

for t in tests {
    let res = detectShoppingIntent(in: t)
    print("[\(res.isShopping ? "Y" : "N")] Query: '\(res.query ?? "nil")' | Text: \(t)")
}
