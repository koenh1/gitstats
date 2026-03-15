import Foundation

/// Represents a single git commit with its hash, date, and author.
public struct GitCommit: Identifiable, Hashable, Sendable {
    public let id: String  // commit hash
    public let date: Date
    public let author: String
    
    public var hash: String { id }
    
    public init(hash: String, date: Date, author: String) {
        self.id = hash
        self.date = date
        self.author = AuthorNormalizer.normalize(author)
    }
}
