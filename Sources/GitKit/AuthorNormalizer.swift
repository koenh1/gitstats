import Foundation

/// Normalizes author name variations to a canonical form.
///
/// Handles common spelling variations:
///   - "firstname.lastname" → "firstname lastname"
///   - "Firstname.Lastname" → "firstname lastname"
///   - "Firstname Lastname"  → "firstname lastname"
///   - "Lastname, Firstname" → "firstname lastname"
public struct AuthorNormalizer {
    
    public static func normalize(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespaces)
      if let index = result.firstIndex(of: "\\") {
        result = .init(result[result.index(after: index)...])
      }
        
        // Lowercase
        result = result.lowercased()
        
        // Replace dots with spaces
        result = result.replacingOccurrences(of: ".", with: " ")
        
        // Handle "lastname, firstname" → "firstname lastname"
        if let commaRange = result.range(of: ",") {
            let before = result[result.startIndex..<commaRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let after = result[commaRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            if !after.isEmpty {
                result = "\(after) \(before)"
            }
        }
        
        // Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        return result.trimmingCharacters(in: .whitespaces)
    }
}
