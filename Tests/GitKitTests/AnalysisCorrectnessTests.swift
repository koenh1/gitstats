import Foundation
import XCTest

@testable import ChartEngine
@testable import GitKit

/// Tests the analysis pipeline against a deterministic test repository.
///
/// The test repo (created by `create_test_repo.sh`) has a known structure:
///
///   Phase 1 (commits 1-10): Each adds a 100-line file
///     - Commits 1,3,5,7,9:  file1.txt .. file5.txt  (dates: 2023-01 through 2023-09)
///     - Commits 2,4,6,8,10: file1.md  .. file5.md   (dates: 2023-02 through 2023-10)
///
///   Phase 2 (commits 11-20): Each modifies 50 lines in an existing file
///     - Commits 11-20: modify files (dates: 2023-11 through 2024-08)
///
///   At HEAD: 10 files × 100 lines = 1000 lines total
///            500 lines from Phase 1, 500 lines from Phase 2
///
final class AnalysisCorrectnessTests: XCTestCase {

    var testRepoURL: URL {
        URL(fileURLWithPath: "/tmp/gitstats-test-repo")
    }

    // MARK: - Basic Repository Tests

    func testRepoHas20Commits() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let commits = try await repo.allCommits()
        XCTAssertEqual(commits.count, 20, "Test repo should have exactly 20 commits")
    }

    func testRepoHas10FilesAtHead() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let commits = try await repo.allCommits()
        let files = try await repo.trackedFiles(at: commits.last!.hash)
        XCTAssertEqual(files.count, 10, "HEAD should have 10 files")

        let txtFiles = files.filter { $0.path.hasSuffix(".txt") }
        let mdFiles = files.filter { $0.path.hasSuffix(".md") }
        XCTAssertEqual(txtFiles.count, 5, "Should have 5 .txt files")
        XCTAssertEqual(mdFiles.count, 5, "Should have 5 .md files")
    }

    func testEachFileHas100LinesAtHead() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let commits = try await repo.allCommits()
        let headHash = commits.last!.hash

        let files = try await repo.trackedFiles(at: headHash)
        for file in files {
            let timestamps = try GitBlame.lineTimestamps(
                repoPath: testRepoURL,
                commitHash: headHash,
                filePath: file.path
            )
            XCTAssertEqual(
                timestamps.count, 100,
                "\(file.path) should have 100 lines at HEAD, got \(timestamps.count)")
        }
    }

    // MARK: - Full Analysis at HEAD (all 20 commits sampled)

    func testFullAnalysisAllCommits() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,  // sample all commits
            fileExtensions: Set([".txt", ".md"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        // At the last commit (HEAD), total line count should be 1000
        // (10 files × 100 lines)
        let headDate = buckets.map(\.commitDate).max()!
        let headBuckets = buckets.filter { $0.commitDate == headDate }
        let totalLinesAtHead = headBuckets.reduce(0) { $0 + $1.lineCount }
        XCTAssertEqual(
            totalLinesAtHead, 1000,
            "HEAD should have exactly 1000 lines (10 files × 100 lines)")

        // Check per-extension totals at HEAD
        let txtLinesAtHead = headBuckets.filter { $0.fileExtension == ".txt" }
            .reduce(0) { $0 + $1.lineCount }
        let mdLinesAtHead = headBuckets.filter { $0.fileExtension == ".md" }
            .reduce(0) { $0 + $1.lineCount }
        XCTAssertEqual(txtLinesAtHead, 500, "HEAD should have 500 .txt lines")
        XCTAssertEqual(mdLinesAtHead, 500, "HEAD should have 500 .md lines")

        print("  ✅ HEAD total: \(totalLinesAtHead) lines (\(txtLinesAtHead) .txt + \(mdLinesAtHead) .md)")
    }

    func testAnalysisProgressiveGrowth() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,
            fileExtensions: Set([".txt", ".md"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        // Group by commit date and compute totals
        let commitDates = Set(buckets.map(\.commitDate)).sorted()
        var prevTotal = 0
        for date in commitDates {
            let dateBuckets = buckets.filter { $0.commitDate == date }
            let total = dateBuckets.reduce(0) { $0 + $1.lineCount }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            print(
                "  Commit \(formatter.string(from: date)): \(total) lines (\(dateBuckets.count) buckets)"
            )

            // After the first commit, line count should only grow during Phase 1
            // and stay at 1000 during Phase 2 (modifications don't change total lines)
            if prevTotal > 0 {
                XCTAssertGreaterThanOrEqual(
                    total, prevTotal,
                    "Total lines should not decrease (at \(formatter.string(from: date)))")
            }
            prevTotal = total
        }
    }

    // MARK: - Extension Filtering

    func testAnalysisTxtOnly() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,
            fileExtensions: Set([".txt"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        // All buckets should be .txt
        for bucket in buckets {
            XCTAssertEqual(bucket.fileExtension, ".txt", "Should only have .txt buckets")
        }

        // At HEAD: 5 .txt files × 100 lines = 500
        let headDate = buckets.map(\.commitDate).max()!
        let headTotal = buckets.filter { $0.commitDate == headDate }.reduce(0) { $0 + $1.lineCount }
        XCTAssertEqual(headTotal, 500, "HEAD with .txt only should have 500 lines")
    }

    func testAnalysisMdOnly() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,
            fileExtensions: Set([".md"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        for bucket in buckets {
            XCTAssertEqual(bucket.fileExtension, ".md", "Should only have .md buckets")
        }

        let headDate = buckets.map(\.commitDate).max()!
        let headTotal = buckets.filter { $0.commitDate == headDate }.reduce(0) { $0 + $1.lineCount }
        XCTAssertEqual(headTotal, 500, "HEAD with .md only should have 500 lines")
    }

    // MARK: - Period Assignment

    func testPeriodAssignment() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,
            fileExtensions: Set([".txt", ".md"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        // At HEAD, lines should be assigned to the quarter they were last written in
        let headDate = buckets.map(\.commitDate).max()!
        let headBuckets = buckets.filter { $0.commitDate == headDate }

        // Print the period breakdown
        var periodTotals: [String: Int] = [:]
        for bucket in headBuckets {
            periodTotals[bucket.period, default: 0] += bucket.lineCount
        }
        print("  Period breakdown at HEAD:")
        for (period, count) in periodTotals.sorted(by: { $0.key < $1.key }) {
            print("    \(period): \(count) lines")
        }

        // All 1000 lines should be accounted for
        let grandTotal = periodTotals.values.reduce(0, +)
        XCTAssertEqual(grandTotal, 1000, "All 1000 lines should be assigned to a period")

        // We know the date ranges, so we can check specific periods exist:
        // Phase 1 dates: 2023-Q1 through 2023-Q4 (original lines)
        // Phase 2 dates: 2023-Q4 through 2024-Q3 (modified lines)
        XCTAssertTrue(periodTotals.keys.contains("2023-Q1"), "Should have lines from 2023-Q1")
    }

    // MARK: - Commit Growth Curve

    func testFirstCommitHas100Lines() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,
            fileExtensions: Set([".txt", ".md"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        let firstDate = buckets.map(\.commitDate).min()!
        let firstTotal = buckets.filter { $0.commitDate == firstDate }
            .reduce(0) { $0 + $1.lineCount }
        XCTAssertEqual(firstTotal, 100, "First commit should have 100 lines (1 file)")
    }

    func testTenthCommitHas1000Lines() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,
            fileExtensions: Set([".txt", ".md"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        // Sort commit dates — the 10th unique date is after all files were added
        let commitDates = Set(buckets.map(\.commitDate)).sorted()
        XCTAssertEqual(commitDates.count, 20)

        // At commit 10, all 10 files exist, each with 100 lines
        let tenthDate = commitDates[9]
        let tenthTotal = buckets.filter { $0.commitDate == tenthDate }
            .reduce(0) { $0 + $1.lineCount }
        XCTAssertEqual(
            tenthTotal, 1000,
            "After 10 commits (all files added), should have 1000 lines, got \(tenthTotal)")

        // After commit 11, still 1000 lines (modification doesn't change count)
        let eleventhDate = commitDates[10]
        let eleventhTotal = buckets.filter { $0.commitDate == eleventhDate }
            .reduce(0) { $0 + $1.lineCount }
        XCTAssertEqual(
            eleventhTotal, 1000,
            "After modification commit, should still have 1000 lines, got \(eleventhTotal)")
    }

    // MARK: - Chart Data Sanity

    func testChartDataProducesCorrectSeries() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 20,
            fileExtensions: Set([".txt", ".md"]),
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)

        // Aggregate by (commitDate, period) before building chart
        let chartBuckets = Dictionary(
            grouping: buckets,
            by: { "\($0.commitDate.timeIntervalSince1970)-\($0.period)" }
        ).map { (_, group) in
            StackedAreaChart.Bucket(
                commitDate: group[0].commitDate,
                period: group[0].period,
                lineCount: group.reduce(0) { $0 + $1.lineCount }
            )
        }

        let chartData = StackedAreaChart.build(from: chartBuckets)

        XCTAssertFalse(chartData.isEmpty, "Chart data should not be empty")
        XCTAssertEqual(chartData.commitDates.count, 20, "Should have 20 commit dates")
        XCTAssertGreaterThan(chartData.series.count, 0, "Should have at least one period series")
        XCTAssertEqual(chartData.maxLineCount, 1000, "Max line count should be 1000")

        print("  Chart: \(chartData.commitDates.count) dates, \(chartData.series.count) series")
        print("  Max line count: \(chartData.maxLineCount)")
    }
}
