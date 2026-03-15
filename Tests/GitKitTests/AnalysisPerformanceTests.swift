import XCTest
import Foundation
@testable import GitKit
@testable import ChartEngine

final class AnalysisPerformanceTests: XCTestCase {
    
    // Use the gitstats repo itself as the test subject.
    // Override with GITSTATS_TEST_REPO env var to test with a different repo.
    var testRepoURL: URL {
        // Default: use the gitstats repo itself (parent of build dir)
        // Walk up from the test bundle to find the repo root
        let thisFile = URL(fileURLWithPath: #file)
        // #file = .../Tests/GitKitTests/AnalysisPerformanceTests.swift
        // repo root = 3 levels up
        return thisFile
        .deletingLastPathComponent().appendingPathComponent("scikit-lego")
    }
    
    // MARK: - Baseline Performance Tests
    
    /// Measures total time for the full analysis pipeline with 10 sampled commits.
    func testFullAnalysisPipeline_10Commits() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let config = AnalysisConfig(
            sampleCount: 10,
            fileExtensions: nil, // all files
            granularity: .quarter
        )
        let engine = AnalysisEngine(repo: repo)
        
        let start = CFAbsoluteTimeGetCurrent()
        let buckets = try await engine.analyze(config: config)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        print("═══════════════════════════════════════════")
        print("  Full pipeline (10 commits): \(String(format: "%.2f", elapsed))s")
        print("  Buckets produced: \(buckets.count)")
        print("  Total lines tracked: \(buckets.reduce(0) { $0 + $1.lineCount })")
        print("═══════════════════════════════════════════")
        
        XCTAssertFalse(buckets.isEmpty, "Should produce at least some buckets")
    }
    
    /// Measures total time for 50 sampled commits (typical usage).
    func testFullAnalysisPipeline_50Commits() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let config = AnalysisConfig(
            sampleCount: 50,
            fileExtensions: nil,
            granularity: .quarter
        )
        let engine = AnalysisEngine(repo: repo)
        
        let start = CFAbsoluteTimeGetCurrent()
        let buckets = try await engine.analyze(config: config)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        print("═══════════════════════════════════════════")
        print("  Full pipeline (50 commits): \(String(format: "%.2f", elapsed))s")
        print("  Buckets produced: \(buckets.count)")
        print("  Total lines tracked: \(buckets.reduce(0) { $0 + $1.lineCount })")
        print("═══════════════════════════════════════════")
        
        XCTAssertFalse(buckets.isEmpty, "Should produce at least some buckets")
    }
    
    // MARK: - Component Benchmarks
    
    /// Measures just the commit listing performance.
    func testCommitListingPerformance() async throws {
        let repo = try GitRepository(path: testRepoURL)
        
        let start = CFAbsoluteTimeGetCurrent()
        let commits = try await repo.allCommits()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        print("  Commit listing: \(String(format: "%.3f", elapsed))s — \(commits.count) commits")
        XCTAssertFalse(commits.isEmpty)
    }
    
    /// Measures file listing at HEAD.
    func testFileListingPerformance() async throws {
        let repo = try GitRepository(path: testRepoURL)
        
        let start = CFAbsoluteTimeGetCurrent()
        let commits = try await repo.allCommits()
        let files = try await repo.trackedFiles(at: commits.last!.hash)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        print("  File listing: \(String(format: "%.3f", elapsed))s — \(files.count) files")
        XCTAssertFalse(files.isEmpty)
    }
    
    /// Measures a single commit blame (all files).
    func testSingleCommitBlamePerformance() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let commits = try await repo.allCommits()
        guard let lastCommit = commits.last else {
            XCTFail("No commits"); return
        }
        let files = try await repo.trackedFiles(at: lastCommit.hash)
        
        let start = CFAbsoluteTimeGetCurrent()
        var totalLines = 0
        for file in files {
            let timestamps = try GitBlame.lineTimestamps(
                repoPath: testRepoURL,
                commitHash: lastCommit.hash,
                filePath: file.path
            )
            totalLines += timestamps.count
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        print("  Single commit blame: \(String(format: "%.2f", elapsed))s — \(files.count) files, \(totalLines) lines")
    }
    
    /// Measures the aggregation step in isolation with synthetic data.
    func testAggregationPerformance() {
        // Simulate a large dataset: 50 commits × 10,000 lines each = 500,000 entries
        let calendar = Calendar(identifier: .gregorian)
        var rawData: [(commitTimestamp: TimeInterval, lineTimestamp: TimeInterval)] = []
        let baseTime: TimeInterval = 1_600_000_000
        
        for commit in 0..<50 {
            let commitTS = baseTime + Double(commit) * 86400 * 30 // monthly commits
            for line in 0..<10_000 {
                let lineTS = baseTime + Double(line % 500) * 86400 * 7 // various ages
                rawData.append((commitTS, lineTS))
            }
        }
        
        let start = CFAbsoluteTimeGetCurrent()
        
        var commitDateByKey: [String: Date] = [:]
        var bucketMap: [String: [String: Int]] = [:]
        
        for entry in rawData {
            let commitDate = Date(timeIntervalSince1970: entry.commitTimestamp)
            let lineDate = Date(timeIntervalSince1970: entry.lineTimestamp)
            
            let comps = calendar.dateComponents([.year, .month, .day], from: commitDate)
            let commitKey = String(format: "%04d-%02d-%02d", comps.year!, comps.month!, comps.day!)
            
            let lineComps = calendar.dateComponents([.year, .month], from: lineDate)
            let quarter = ((lineComps.month! - 1) / 3) + 1
            let period = String(format: "%04d-Q%d", lineComps.year!, quarter)
            
            if commitDateByKey[commitKey] == nil {
                commitDateByKey[commitKey] = commitDate
            }
            bucketMap[commitKey, default: [:]][period, default: 0] += 1
        }
        
        var results: [LineAgeBucket] = []
        for (commitKey, periods) in bucketMap {
            guard let commitDate = commitDateByKey[commitKey] else { continue }
            for (period, count) in periods {
                results.append(LineAgeBucket(commitDate: commitDate, period: period, lineCount: count, fileExtension: ".test", filePath: "test.test", commitAuthor: "Test"))
            }
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        print("  Aggregation (500K entries): \(String(format: "%.3f", elapsed))s — \(results.count) buckets")
        XCTAssertFalse(results.isEmpty)
    }
    
    /// Measures ChartEngine build performance.
    func testChartBuildPerformance() {
        // Create realistic buckets: 50 commit dates × 20 periods
        var buckets: [StackedAreaChart.Bucket] = []
        let baseTime: TimeInterval = 1_600_000_000
        
        for commit in 0..<50 {
            let commitDate = Date(timeIntervalSince1970: baseTime + Double(commit) * 86400 * 30)
            for q in 0..<20 {
                let lineCount = Int.random(in: 100...5000)
                let year = 2020 + q / 4
                let quarter = (q % 4) + 1
                buckets.append(StackedAreaChart.Bucket(
                    commitDate: commitDate,
                    period: "\(year)-Q\(quarter)",
                    lineCount: lineCount
                ))
            }
        }
        
        let start = CFAbsoluteTimeGetCurrent()
        let chartData = StackedAreaChart.build(from: buckets)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        print("  Chart build (1000 buckets): \(String(format: "%.3f", elapsed))s — \(chartData.series.count) series")
        XCTAssertFalse(chartData.isEmpty)
    }
}
