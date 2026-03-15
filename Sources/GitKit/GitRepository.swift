import Foundation

/// Errors that can occur during git operations.
public enum GitError: Error, LocalizedError {
    case notAGitRepository(String)
    case commandFailed(String)
    case parseError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notAGitRepository(let path):
            return "Not a git repository: \(path)"
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

/// Represents a local git repository and provides methods to query its history.
public actor GitRepository {
    public let path: URL
    
    public init(path: URL) throws {
        let gitDir = path.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else {
            throw GitError.notAGitRepository(path.path)
        }
        self.path = path
    }
    
    // MARK: - Commit History
    
    /// Returns all commits in chronological order (oldest first).
    public func allCommits() throws -> [GitCommit] {
        let output = try runGit(["log", "--format=%H\t%at\t%aN", "--reverse"])
        var commits: [GitCommit] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard parts.count >= 3,
                  let timestamp = TimeInterval(parts[1]) else { continue }
            let hash = String(parts[0])
            let date = Date(timeIntervalSince1970: timestamp)
            let author = String(parts[2])
            commits.append(GitCommit(hash: hash, date: date, author: author))
        }
        return commits
    }
    
    // MARK: - File Listing
    
    /// A file tracked at a specific commit, with its blob hash.
    public struct TrackedFile: Sendable {
        public let path: String
        public let blobHash: String
    }
    
    /// Returns all tracked files at a given commit, optionally filtering by extension or explicit path set.
    public func trackedFiles(
        at commitHash: String,
        extensions: Set<String>? = nil,
        paths: Set<String>? = nil
    ) throws -> [TrackedFile] {
        let output = try runGit(["ls-tree", "-r", commitHash])
        var files: [TrackedFile] = []
        for line in output.split(separator: "\n") {
            // Format: <mode> <type> <blob_hash>\t<path>
            guard let tabIndex = line.firstIndex(of: "\t") else { continue }
            let meta = line[line.startIndex..<tabIndex]
            let filePath = String(line[line.index(after: tabIndex)...])
            let metaParts = meta.split(separator: " ")
            guard metaParts.count >= 3 else { continue }
            let blobHash = String(metaParts[2])
            
            // Filter by explicit path set if specified
            if let paths = paths {
                guard paths.contains(filePath) else { continue }
            }
            
            // Filter by extension if specified
            if let extensions = extensions {
                let ext = (filePath as NSString).pathExtension
                guard !ext.isEmpty, extensions.contains(".\(ext)") else { continue }
            }
            
            files.append(TrackedFile(path: filePath, blobHash: blobHash))
        }
        return files
    }
    
    /// Returns all tracked file paths at HEAD.
    public func trackedFilePaths() throws -> [String] {
        let output = try runGit(["ls-tree", "-r", "--name-only", "HEAD"])
        return output.split(separator: "\n").map(String.init)
    }
    
    // MARK: - Extension Discovery
    
    /// Known text file extensions.
    public static let knownTextExtensions: Set<String> = [
        // Programming languages
        ".swift", ".py", ".js", ".ts", ".tsx", ".jsx", ".java", ".kt", ".kts",
        ".c", ".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx", ".m", ".mm",
        ".go", ".rs", ".rb", ".php", ".pl", ".pm", ".lua", ".r", ".R",
        ".scala", ".clj", ".cljs", ".erl", ".ex", ".exs", ".hs", ".elm",
        ".cs", ".fs", ".fsx", ".vb", ".dart", ".zig", ".nim", ".v",
        ".lean", ".lean4",
        // Web
        ".html", ".htm", ".css", ".scss", ".sass", ".less", ".vue", ".svelte",
        // Data / Config
        ".json", ".yaml", ".yml", ".toml", ".xml", ".xsl", ".xsd", ".csv", ".tsv", ".ini",
        ".cfg", ".conf", ".env", ".properties", ".plist", ".ttl", ".rdf",
        // Documentation
        ".md", ".markdown", ".rst", ".txt", ".adoc", ".tex", ".org",
        // Shell / Scripts
        ".sh", ".bash", ".zsh", ".fish", ".bat", ".cmd", ".ps1", ".psm1",
        // Build / CI
        ".cmake", ".make", ".makefile", ".gradle", ".sbt",
        ".dockerfile", ".containerfile",
        // Other text
        ".sql", ".graphql", ".gql", ".proto", ".thrift", ".avsc",
        ".tf", ".hcl", ".nix", ".el", ".vim", ".awk", ".sed",
        ".gitignore", ".gitattributes", ".editorconfig",
        ".lock", ".sum", ".mod",
        ".pyx", ".pxd", ".pyi",  ".cu", ".cuh",
    ]
    
    /// Statistics for a file extension in the repository.
    public struct ExtensionStats: Sendable, Identifiable {
        public let ext: String          // e.g. ".swift"
        public let fileCount: Int
        public let lineCount: Int       // actual or estimated
        public let isTextType: Bool
        public var id: String { ext }
    }
    
    /// Returns all file extensions in the repo at HEAD with file counts, line counts,
    /// and text classification, sorted by file count descending.
    public func fileExtensionStats() throws -> [ExtensionStats] {
        // 1. Get all files with sizes: git ls-tree -r -l HEAD
        let lsOutput = try runGit(["ls-tree", "-r", "-l", "HEAD"])
        
        struct FileInfo {
            let path: String
            let size: Int
        }
        
        // Group files by extension
        var filesByExt: [String: [FileInfo]] = [:]
        for line in lsOutput.split(separator: "\n") {
            // Format: <mode> <type> <hash> <size>\t<path>
            guard let tabIndex = line.firstIndex(of: "\t") else { continue }
            let meta = String(line[line.startIndex..<tabIndex])
            let filePath = String(line[line.index(after: tabIndex)...])
            let ext = (filePath as NSString).pathExtension
            
            let metaParts = meta.split(separator: " ").filter { !$0.isEmpty }
            guard metaParts.count >= 4, let size = Int(metaParts[3]) else { continue }
            
            // Treat extensions >4 chars or containing uppercase as "no extension"
            let isValidExt = !ext.isEmpty && ext.count <= 4 && ext == ext.lowercased()
            let dotExt = isValidExt ? ".\(ext)" : "(none)"
            filesByExt[dotExt, default: []].append(FileInfo(path: filePath, size: size))
        }
        
        // 2. Get line counts for text files: git grep -c '' HEAD
        //    This efficiently counts lines and auto-skips binary files.
        var lineCountByFile: [String: Int] = [:]
        if let grepOutput = try? runGit(["grep", "-c", "", "HEAD"]) {
            for line in grepOutput.split(separator: "\n") {
                // Format: HEAD:<path>:<count>
                let str = String(line)
                guard str.hasPrefix("HEAD:") else { continue }
                let rest = str.dropFirst(5) // drop "HEAD:"
                guard let lastColon = rest.lastIndex(of: ":") else { continue }
                let filePath = String(rest[rest.startIndex..<lastColon])
                let countStr = String(rest[rest.index(after: lastColon)...])
                if let count = Int(countStr) {
                    lineCountByFile[filePath] = count
                }
            }
        }
        
        // 3. Build stats per extension
        let sizeThreshold = 1_000_000 // 1 MB
        
        var results: [ExtensionStats] = []
        for (ext, files) in filesByExt {
            let isText = Self.knownTextExtensions.contains(ext.lowercased())
            let fileCount = files.count
            
            if isText {
                // Count lines: actual for small files, estimated for large ones
                var totalLines = 0
                var smallFileLines = 0
                var smallFileBytes = 0
                var largeFileBytes = 0
                
                for file in files {
                    if file.size <= sizeThreshold {
                        let lines = lineCountByFile[file.path] ?? 0
                        totalLines += lines
                        smallFileLines += lines
                        smallFileBytes += file.size
                    } else {
                        largeFileBytes += file.size
                    }
                }
                
                // Estimate lines for large files based on avg lines/byte from small files
                if largeFileBytes > 0 {
                    let avgLinesPerByte = smallFileBytes > 0
                        ? Double(smallFileLines) / Double(smallFileBytes)
                        : 0.025  // fallback: ~25 lines per KB
                    totalLines += Int(Double(largeFileBytes) * avgLinesPerByte)
                }
                
                results.append(ExtensionStats(
                    ext: ext, fileCount: fileCount, lineCount: totalLines, isTextType: true
                ))
            } else {
                results.append(ExtensionStats(
                    ext: ext, fileCount: fileCount, lineCount: 0, isTextType: false
                ))
            }
        }
        
        return results.sorted { $0.fileCount > $1.fileCount }
    }
    
    // MARK: - Git Command Runner
    
    func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = path
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        
        // Read pipe data BEFORE waitUntilExit to avoid deadlock when output > 64KB buffer
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw GitError.commandFailed(
                "git \(arguments.joined(separator: " ")) exited with code \(process.terminationStatus)"
            )
        }
        
        return String(decoding: data, as: UTF8.self)
    }
    
    // MARK: - Pom Version
    
    /// Reads the major.minor version from pom.xml at a specific commit.
    /// Returns nil if no pom.xml exists or no version can be parsed.
    public func pomMajorMinorVersion(at commitHash: String) -> String? {
        guard let content = try? runGit(["show", "\(commitHash):pom.xml"]) else { return nil }
        return PomVersionExtractor().extractVersion(from: content)?.majorMinor
    }
    
    /// Returns true if the repo has a pom.xml at HEAD.
    public func hasPomXml() -> Bool {
        let result = (try? runGit(["ls-tree", "--name-only", "HEAD", "pom.xml"])) ?? ""
        return result.trimmingCharacters(in: .whitespacesAndNewlines) == "pom.xml"
    }
    
    // MARK: - Version Markers
    
    /// A version marker with a date and label, for overlaying on charts.
    public struct VersionMarker: Sendable {
        public let date: Date
        public let version: String      // major.minor e.g. "1.2"
        public let fullVersion: String   // full tag name or version string
        public let author: String        // tagger or commit author
        public let source: String        // "tag" or "pom"
    }
    
    /// Extracts version markers from git tags and/or pom.xml.
    /// For tags: parses semver-like patterns and deduplicates by major.minor.
    /// For version files (pom.xml, etc.): reads the version at each commit, using major.minor only.
    public func versionMarkers() throws -> [VersionMarker] {
        var markers: [VersionMarker] = []
        var seenVersions = Set<String>()
        
        // Try git tags first
        if let tagOutput = try? runGit([
            "tag", "--sort=creatordate",
            "--format=%(creatordate:unix)\t%(refname:short)"
        ]), !tagOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let versionPattern = try NSRegularExpression(
                pattern: #"[vV]?(\d+)\.(\d+)(?:\.\d+)?"#
            )
            
            for line in tagOutput.split(separator: "\n") {
                let str = String(line)
                let tabParts = str.split(separator: "\t", maxSplits: 1)
                guard tabParts.count == 2 else { continue }
                let tsStr = String(tabParts[0]).trimmingCharacters(in: .whitespaces)
                let tagName = String(tabParts[1])
                guard let ts = TimeInterval(tsStr) else { continue }
                
                let range = NSRange(tagName.startIndex..., in: tagName)
                guard let match = versionPattern.firstMatch(in: tagName, range: range) else { continue }
                
                let majorRange = Range(match.range(at: 1), in: tagName)!
                let minorRange = Range(match.range(at: 2), in: tagName)!
                let majorMinor = "\(tagName[majorRange]).\(tagName[minorRange])"
                
                guard !seenVersions.contains(majorMinor) else { continue }
                seenVersions.insert(majorMinor)
                
                // Get author of the tagged commit
                let author = (try? runGit(["log", "-1", "--format=%aN", tagName]))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                markers.append(VersionMarker(
                    date: Date(timeIntervalSince1970: ts),
                    version: majorMinor,
                    fullVersion: tagName,
                    author: author,
                    source: "tag"
                ))
            }
        }
        
        // If no tag-based markers found, try version files
        if markers.isEmpty {
            for extractor in VersionExtractors.all {
                markers = try versionFileMarkers(extractor: extractor)
                if !markers.isEmpty { break }
            }
        }
        
        return markers.sorted { $0.date < $1.date }
    }
    
    /// Extract versions from a version file across the repo history using the given extractor.
    /// If all extracted versions share the same major.minor, uses major.minor.patch for dedup.
    private func versionFileMarkers(extractor: VersionExtractor) throws -> [VersionMarker] {
        let filename = extractor.filename
        
        // Check if the file exists at HEAD
        let hasFile = (try? runGit(["ls-tree", "--name-only", "HEAD", filename])) ?? ""
        guard hasFile.trimmingCharacters(in: .whitespacesAndNewlines) == filename else {
            return []
        }
        
        // Get commits that modified the file (oldest first) with timestamps and author
        let logOutput = try runGit([
            "log", "--format=%H %at %aN", "--reverse", "--diff-filter=AM", "--", filename
        ])
        
        // Derive source name from filename
        let source = filename.hasSuffix(".xml")
            ? String(filename.dropLast(4))
            : filename
        
        // First pass: collect all entries with extracted versions
        struct VersionEntry {
            let date: Date
            let author: String
            let extracted: ExtractedVersion
        }
        
        var entries: [VersionEntry] = []
        for line in logOutput.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count >= 2,
                  let ts = TimeInterval(parts[1]) else { continue }
            let hash = String(parts[0])
            let author = parts.count >= 3 ? String(parts[2]) : ""
            
            guard let content = try? runGit(["show", "\(hash):\(filename)"]),
                  let extracted = extractor.extractVersion(from: content) else { continue }
            
            entries.append(VersionEntry(
                date: Date(timeIntervalSince1970: ts),
                author: author,
                extracted: extracted
            ))
        }
        
        guard !entries.isEmpty else { return [] }
        
        // If all majorMinor values are the same, use patch-level granularity
        let uniqueMajorMinors = Set(entries.map(\.extracted.majorMinor))
        let usePatch = uniqueMajorMinors.count <= 1
        
        // Second pass: build markers with chosen granularity
        var markers: [VersionMarker] = []
        var seenVersions = Set<String>()
        
        for entry in entries {
            let versionKey = usePatch ? entry.extracted.majorMinorPatch : entry.extracted.majorMinor
            guard !seenVersions.contains(versionKey) else { continue }
            seenVersions.insert(versionKey)
            
            markers.append(VersionMarker(
                date: entry.date,
                version: versionKey,
                fullVersion: entry.extracted.fullVersion,
                author: entry.author,
                source: source
            ))
        }
        
        return markers
    }
}
