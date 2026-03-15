import Foundation

/// Data point representing the line count for a specific period at a specific commit.
public struct LineAgeBucket: Sendable {
    public let commitDate: Date
    public let period: String  // e.g. "2023" or "2023-Q1"
    public let lineCount: Int
    public let fileExtension: String  // e.g. ".swift"
    public let filePath: String  // e.g. "Sources/Foo.swift"
    public let commitAuthor: String  // e.g. "Alice"
}

/// Configuration for the analysis.
public struct AnalysisConfig: Sendable {
    public var sampleCount: Int
    public var fileExtensions: Set<String>?  // legacy, still used by tests
    public var filePaths: Set<String>?  // explicit set of file paths to include
    public var authors: Set<String>?  // nil = all authors
    public var granularity: TimeGranularity
    public var refineSamplingWithPom: Bool  // binary-search for version transitions

    public enum TimeGranularity: String, CaseIterable, Sendable {
        case year = "Year"
        case quarter = "Quarter"
        case month = "Month"
        case week = "Week"
        case day = "Day"
    }

    public init(
        sampleCount: Int = 100,
        fileExtensions: Set<String>? = nil,
        filePaths: Set<String>? = nil,
        authors: Set<String>? = nil,
        granularity: TimeGranularity = .quarter,
        refineSamplingWithPom: Bool = false
    ) {
        self.sampleCount = sampleCount
        self.fileExtensions = fileExtensions
        self.filePaths = filePaths
        self.authors = authors
        self.granularity = granularity
        self.refineSamplingWithPom = refineSamplingWithPom
    }
}

struct CommitKey: Hashable, Sendable {
    let author: String
    let ext: String
    let path: String
}

/// Progress reporting during analysis.
public struct AnalysisProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let currentCommit: String

    public var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }
}

/// The main analysis engine that orchestrates blame data collection across commits.
public actor AnalysisEngine {
    private let repo: GitRepository

    /// Cache: blob hash → blame lines (timestamp + author). Identical blobs have identical blame.
    private var blameCache: [String: [GitBlame.BlameLine]] = [:]
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    public init(repo: GitRepository) {
        self.repo = repo
    }

    /// Reads pom.xml major.minor version at a commit by shelling out directly.
    /// This is a nonisolated static method so it can be called from synchronous closures.
    nonisolated static func readPomVersion(at hash: String, repoPath: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["show", "\(hash):pom.xml"]
        process.currentDirectoryURL = repoPath
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let content = String(decoding: data, as: UTF8.self)
        return PomVersionExtractor().extractVersion(from: content)?.majorMinor
    }

    /// Runs the full analysis pipeline and returns aggregated line-age buckets.
    public func analyze(
        config: AnalysisConfig,
        onProgress: @Sendable (AnalysisProgress) -> Void = { _ in }
    ) async throws -> [LineAgeBucket] {
        // Reset cache stats for this run
        blameCache.removeAll()
        cacheHits = 0
        cacheMisses = 0

        // 1. Get all commits, optionally filtered by author
        var allCommits = try await repo.allCommits()
        if let authors = config.authors {
            allCommits = allCommits.filter { authors.contains($0.author) }
        }
        guard !allCommits.isEmpty else { return [] }

        let repoPath = repo.path

        // 2. Sample evenly, then refine with version transitions if requested
        var sampled = CommitSampler.sample(allCommits, count: config.sampleCount)

        if config.refineSamplingWithPom {
            let path = repoPath
            sampled = CommitSampler.refineWithVersionTransitions(
                sampled: sampled,
                allCommits: allCommits,
                versionAt: { hash in
                    Self.readPomVersion(at: hash, repoPath: path)
                }
            )
            print(
                "Version-refined sampling: \(sampled.count) commits (from \(config.sampleCount) initial)"
            )
        }

        // 3. Collect blame data for each sampled commit, tagged with a sample index
        //    so that each commit stays a distinct snapshot (even if two commits share a day).
        struct RawEntry {
            let sampleIndex: Int
            let commitTimestamp: TimeInterval
            let lineTimestamp: TimeInterval
            let info: CommitKey
        }
        var allRawData: [RawEntry] = []

        for (index, commit) in sampled.enumerated() {
            let data = try await analyzeCommit(
                repoPath: repoPath,
                commit: commit,
                extensions: config.fileExtensions,
                paths: config.filePaths
            )
            for d in data {
                allRawData.append(
                    RawEntry(
                        sampleIndex: index,
                        commitTimestamp: d.0,
                        lineTimestamp: d.1,
                        info: d.2
                    ))
            }

            onProgress(
                AnalysisProgress(
                    completed: index + 1,
                    total: sampled.count,
                    currentCommit: String(commit.hash.prefix(8))
                ))
        }

        print(
            "Blame cache: \(cacheHits) hits, \(cacheMisses) misses (\(blameCache.count) unique blobs)"
        )

        // 4. Aggregate into buckets keyed by sample index (not date) to prevent
        //    multiple commits on the same day from merging their line counts.
        let calendar = Calendar(identifier: .gregorian)
        let count = allRawData.count
        guard count > 0 else { return [] }

        let granularity = config.granularity
        var commitDateBySample: [Int: Double] = [:]
        var bucketMap: [Int: [PeriodKey: [CommitKey: Int]]] = [:]

        // Pre-compute PeriodKey for each entry by sorting indices by lineTimestamp
        var periodKeyArray = [PeriodKey](
            repeating: PeriodKey(date: Date(), granularity: granularity, calendar: calendar),
            count: count)
        let lineSortedIndices = (0..<count).sorted {
            allRawData[$0].lineTimestamp < allRawData[$1].lineTimestamp
        }
        var prevLineTS = allRawData[lineSortedIndices[0]].lineTimestamp - 1
        var currentPeriodKey = periodKeyArray[0]
        for idx in lineSortedIndices {
            let ts = allRawData[idx].lineTimestamp
            if ts > prevLineTS {
                prevLineTS = ts
                currentPeriodKey = PeriodKey(
                    date: Date(timeIntervalSince1970: ts), granularity: granularity,
                    calendar: calendar)
            }
            periodKeyArray[idx] = currentPeriodKey
        }

        // Aggregate using sample index as the primary key
        for i in 0..<count {
            let entry = allRawData[i]
            let sampleIdx = entry.sampleIndex
            let period = periodKeyArray[i]

            if commitDateBySample[sampleIdx] == nil {
                commitDateBySample[sampleIdx] = entry.commitTimestamp
            }

            bucketMap[sampleIdx, default: [:]][period, default: [:]][entry.info, default: 0] += 1
        }

        // 5. Convert to output array (one bucket per commit × period × extension)
        var results: [LineAgeBucket] = []
        for (sampleIdx, periods) in bucketMap {
            guard let commitDate = commitDateBySample[sampleIdx] else { continue }
            for (period, infocounts) in periods {
                for (info, lineCount) in infocounts {
                    results.append(
                        LineAgeBucket(
                            commitDate: Date(timeIntervalSince1970: commitDate),
                            period: period.displayString,
                            lineCount: lineCount,
                            fileExtension: info.ext,
                            filePath: info.path,
                            commitAuthor: info.author
                        ))
                }
            }
        }

        results.sort { a, b in
            if a.commitDate != b.commitDate {
                return a.commitDate < b.commitDate
            }
            return a.period < b.period
        }

        return results
    }

    // MARK: - Private

    private func analyzeCommit(
        repoPath: URL,
        commit: GitCommit,
        extensions: Set<String>?,
        paths: Set<String>?
    ) async throws -> [(
        commitTimestamp: TimeInterval, lineTimestamp: TimeInterval, info: CommitKey
    )] {
        let files = try await repo.trackedFiles(
            at: commit.hash, extensions: extensions, paths: paths)
        let commitTS = commit.date.timeIntervalSince1970

        // Separate files into cached (already known) and uncached (need blame)
        var allResults: [(TimeInterval, TimeInterval, CommitKey)] = []
        var uncachedFiles: [GitRepository.TrackedFile] = []

        for file in files {
            let ext = "." + ((file.path as NSString).pathExtension)
            if let cached = blameCache[file.blobHash] {
                // Cache hit — reuse previous blame result
                cacheHits += 1
                for line in cached {
                    allResults.append(
                        (
                            commitTS, line.timestamp,
                            CommitKey(author: line.author, ext: ext, path: file.path)
                        ))
                }
            } else {
                uncachedFiles.append(file)
            }
        }

        // Blame uncached files concurrently
        if !uncachedFiles.isEmpty {
            let blameResults = try await withThrowingTaskGroup(
                of: (String, String, String, [GitBlame.BlameLine]).self,  // (blobHash, ext, filePath, blameLines)
                returning: [(String, String, String, [GitBlame.BlameLine])].self
            ) { group in
                let maxConcurrent = 32
                var pending = 0
                var fileIterator = uncachedFiles.makeIterator()
                var results: [(String, String, String, [GitBlame.BlameLine])] = []

                // Seed initial batch
                for _ in 0..<min(maxConcurrent, uncachedFiles.count) {
                    if let file = fileIterator.next() {
                        let blobHash = file.blobHash
                        let filePath = file.path
                        let fileExt = "." + ((filePath as NSString).pathExtension)
                        group.addTask {
                            let blameLines = try GitBlame.lineInfo(
                                repoPath: repoPath,
                                commitHash: commit.hash,
                                filePath: filePath
                            )
                            return (blobHash, fileExt, filePath, blameLines)
                        }
                        pending += 1
                    }
                }

                // Process results and feed new tasks
                while pending > 0 {
                    if let result = try await group.next() {
                        pending -= 1
                        results.append(result)
                        if let file = fileIterator.next() {
                            let blobHash = file.blobHash
                            let filePath = file.path
                            let fileExt = "." + ((filePath as NSString).pathExtension)
                            group.addTask {
                                let blameLines = try GitBlame.lineInfo(
                                    repoPath: repoPath,
                                    commitHash: commit.hash,
                                    filePath: filePath
                                )
                                return (blobHash, fileExt, filePath, blameLines)
                            }
                            pending += 1
                        }
                    }
                }

                return results
            }

            // Store results in cache and accumulate
            for (blobHash, ext, filePath, blameLines) in blameResults {
                cacheMisses += 1
                blameCache[blobHash] = blameLines
                for line in blameLines {
                    allResults.append(
                        (
                            commitTS, line.timestamp,
                            CommitKey(author: line.author, ext: ext, path: filePath)
                        ))
                }
            }
        }

        return allResults
    }
}

// MARK: - Compact Integer Keys

/// Compact date key stored as YYYYMMDD in a UInt32. Avoids String allocation in hot loops.
struct DateKey: Hashable {
    let raw: UInt32  // e.g. 20240315

    init(date: Date, calendar: Calendar) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        raw = UInt32(comps.year!) * 10000 + UInt32(comps.month!) * 100 + UInt32(comps.day!)
    }
}

/// Compact period key stored as a UInt32.
/// - Year:    YYYY * 10000                 (e.g. 20240000)
/// - Quarter: YYYY * 10000 + Q * 100       (e.g. 20240100 = 2024-Q1)
/// - Month:   YYYY * 10000 + MM * 100      (e.g. 20240300 = 2024-03)
/// - Week:    YYYY * 10000 + WW * 100      (e.g. 20241500 = 2024-W15)
/// - Day:     YYYY * 10000 + MM * 100 + DD (e.g. 20240315 = 2024-03-15)
struct PeriodKey: Hashable {
    let raw: UInt32

    private enum Kind: UInt8 { case year, quarter, month, week, day }
    private let kind: Kind

    init(date: Date, granularity: AnalysisConfig.TimeGranularity, calendar: Calendar) {
        let comps = calendar.dateComponents([.year, .month, .day, .weekOfYear], from: date)
        let year = UInt32(comps.year!)
        let month = UInt32(comps.month!)
        switch granularity {
        case .year:
            raw = year * 10000
            kind = .year
        case .quarter:
            let quarter = (month - 1) / 3 + 1
            raw = year * 10000 + quarter * 100
            kind = .quarter
        case .month:
            raw = year * 10000 + month * 100
            kind = .month
        case .week:
            let week = UInt32(comps.weekOfYear!)
            raw = year * 10000 + week * 100
            kind = .week
        case .day:
            let day = UInt32(comps.day!)
            raw = year * 10000 + month * 100 + day
            kind = .day
        }
    }

    /// Converts back to display string for chart labels.
    var displayString: String {
        let y = raw / 10000
        let rest = raw % 10000
        switch kind {
        case .year:
            return "\(y)"
        case .quarter:
            return "\(y)-Q\(rest / 100)"
        case .month:
            return "\(y)-\(String(format: "%02d", rest / 100))"
        case .week:
            return "\(y)-W\(String(format: "%02d", rest / 100))"
        case .day:
            return
                "\(y)-\(String(format: "%02d", rest / 100))-\(String(format: "%02d", rest % 100))"
        }
    }
}
