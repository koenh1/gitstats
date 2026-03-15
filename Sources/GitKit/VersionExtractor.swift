import Foundation

/// Extracted version information from a project file.
public struct ExtractedVersion: Sendable {
    public let majorMinor: String       // e.g. "1.2"
    public let majorMinorPatch: String   // e.g. "1.2.3" (falls back to majorMinor if no patch)
    public let fullVersion: String       // e.g. "1.2.3-SNAPSHOT"
}

/// Protocol for version extractors — each implementation handles a specific file type.
public protocol VersionExtractor: Sendable {
    /// The filename this extractor handles (e.g. "pom.xml", "package.json").
    var filename: String { get }
    
    /// Extract the version from the file content.
    /// Returns nil if no version can be parsed.
    func extractVersion(from content: String) -> ExtractedVersion?
}

// MARK: - Pom.xml Extractor

/// Extracts version from Maven pom.xml files.
/// Strips <parent> blocks to ensure we get the project's own version, not the parent's.
public struct PomVersionExtractor: VersionExtractor {
    public let filename = "pom.xml"
    
    public init() {}
    
    public func extractVersion(from content: String) -> ExtractedVersion? {
        // Strip <parent>...</parent> to avoid matching parent version
        let stripped = content.replacingOccurrences(
            of: #"<parent>[\s\S]*?</parent>"#, with: "", options: .regularExpression
        )
        
        // Extract major.minor
        guard let majorMinor = extractMajorMinor(from: stripped) else { return nil }
        
        // Extract major.minor.patch (falls back to majorMinor)
        let majorMinorPatch = extractMajorMinorPatch(from: stripped) ?? majorMinor
        
        // Extract full version string
        let fullVersion = extractFullVersion(from: stripped) ?? majorMinor
        
        return ExtractedVersion(
            majorMinor: majorMinor,
            majorMinorPatch: majorMinorPatch,
            fullVersion: fullVersion
        )
    }
    
    private func extractMajorMinor(from content: String) -> String? {
        guard let range = content.range(
            of: #"<version>(\d+)\.(\d+)"#, options: .regularExpression
        ) else { return nil }
        return String(content[range])
            .replacingOccurrences(of: "<version>", with: "")
    }
    
    private func extractMajorMinorPatch(from content: String) -> String? {
        guard let range = content.range(
            of: #"<version>(\d+\.\d+\.\d+)"#, options: .regularExpression
        ) else { return nil }
        return String(content[range])
            .replacingOccurrences(of: "<version>", with: "")
    }
    
    private func extractFullVersion(from content: String) -> String? {
        guard let range = content.range(
            of: #"<version>([^<]+)</version>"#, options: .regularExpression
        ) else { return nil }
        return String(content[range])
            .replacingOccurrences(of: "<version>", with: "")
            .replacingOccurrences(of: "</version>", with: "")
    }
}

// MARK: - Registry

/// Central registry of all available version extractors.
public struct VersionExtractors {
    /// All available extractors, ordered by priority.
    public static let all: [VersionExtractor] = [
        PomVersionExtractor()
    ]
    
    /// Find an extractor by filename.
    public static func extractor(for filename: String) -> VersionExtractor? {
        all.first { $0.filename == filename }
    }
}
