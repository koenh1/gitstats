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
            
            let dotExt = ext.isEmpty ? "(none)" : ".\(ext)"
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
    
    // MARK: - Version Markers
    
    /// A version marker with a date and label, for overlaying on charts.
    public struct VersionMarker: Sendable {
        public let date: Date
        public let version: String  // e.g. "1.2" or "v2.0"
    }
    
    /// Extracts version markers from git tags and/or pom.xml.
    /// For tags: parses semver-like patterns and deduplicates by major.minor.
    /// For pom.xml: reads the <version> at each tag commit, using major.minor only.
    public func versionMarkers() throws -> [VersionMarker] {
        var markers: [VersionMarker] = []
        var seenVersions = Set<String>()
        
        // Try git tags first
        // Format: <unix_timestamp> <tagname>
        if let tagOutput = try? runGit([
            "tag", "--sort=creatordate",
            "--format=%(creatordate:unix) %(refname:short)"
        ]), !tagOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let versionPattern = try NSRegularExpression(
                pattern: #"[vV]?(\d+)\.(\d+)(?:\.\d+)?"#
            )
            
            for line in tagOutput.split(separator: "\n") {
                let str = String(line)
                guard let spaceIdx = str.firstIndex(of: " ") else { continue }
                let tsStr = String(str[str.startIndex..<spaceIdx])
                let tagName = String(str[str.index(after: spaceIdx)...])
                guard let ts = TimeInterval(tsStr) else { continue }
                
                let range = NSRange(tagName.startIndex..., in: tagName)
                guard let match = versionPattern.firstMatch(in: tagName, range: range) else { continue }
                
                let majorRange = Range(match.range(at: 1), in: tagName)!
                let minorRange = Range(match.range(at: 2), in: tagName)!
                let majorMinor = "\(tagName[majorRange]).\(tagName[minorRange])"
                
                guard !seenVersions.contains(majorMinor) else { continue }
                seenVersions.insert(majorMinor)
                
                markers.append(VersionMarker(
                    date: Date(timeIntervalSince1970: ts),
                    version: majorMinor
                ))
            }
        }
        
        // If no tag-based markers found, try pom.xml
        if markers.isEmpty {
            markers = try pomVersionMarkers()
        }
        
        return markers.sorted { $0.date < $1.date }
    }
    
    /// Extract versions from pom.xml across the repo history.
    private func pomVersionMarkers() throws -> [VersionMarker] {
        // Check if pom.xml exists at HEAD
        let hasFile = (try? runGit(["ls-tree", "--name-only", "HEAD", "pom.xml"])) ?? ""
        guard hasFile.trimmingCharacters(in: .whitespacesAndNewlines) == "pom.xml" else {
            return []
        }
        
        // Get commits that modified pom.xml (oldest first) with timestamps
        let logOutput = try runGit([
            "log", "--format=%H %at", "--reverse", "--diff-filter=AM", "--", "pom.xml"
        ])
        
        let versionPattern = try NSRegularExpression(
            pattern: #"<version>(\d+)\.(\d+)(?:\.\d+)*(?:-[A-Za-z0-9.]+)?</version>"#
        )
        
        var markers: [VersionMarker] = []
        var seenVersions = Set<String>()
        
        for line in logOutput.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2,
                  let ts = TimeInterval(parts[1]) else { continue }
            let hash = String(parts[0])
            
            // Read pom.xml at this commit
            guard let content = try? runGit(["show", "\(hash):pom.xml"]) else { continue }
            
            let range = NSRange(content.startIndex..., in: content)
            guard let match = versionPattern.firstMatch(in: content, range: range) else { continue }
            
            let majorRange = Range(match.range(at: 1), in: content)!
            let minorRange = Range(match.range(at: 2), in: content)!
            let majorMinor = "\(content[majorRange]).\(content[minorRange])"
            
            guard !seenVersions.contains(majorMinor) else { continue }
            seenVersions.insert(majorMinor)
            
            markers.append(VersionMarker(
                date: Date(timeIntervalSince1970: ts),
                version: majorMinor
            ))
        }
        
        return markers
    }
}
