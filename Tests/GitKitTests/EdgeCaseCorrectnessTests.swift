import Foundation
import XCTest

@testable import ChartEngine
@testable import GitKit

/// Tests the analysis pipeline against an edge-case test repository.
///
/// The edge-case repo (created by `create_edge_case_repo.sh`) has 12 commits:
///
///   C1:  50 lines  (add 5 files × 10 lines)
///   C2:  100 lines (add 5 more files × 10 lines)
///   C3:  105 lines (+5 to file1)
///   C4:  102 lines (-3 from file2, SAME DAY as C3)
///   C5:  102 lines (alter file3, no count change)
///   C6:  102 lines (+2 file4, -2 file5, net 0)
///   C7:  102 lines (alter file6+file7, SAME DAY as C6)
///   C8:  102 lines (rename file8, no count change)
///   C9:  92 lines  (delete file9)
///   C10: 87 lines  (revert file1 to original)
///   C11: 90 lines  (+3 to file10, SAME DAY as C10)
///   C12: 105 lines (+15 to file1+file2+file3)
///
final class EdgeCaseCorrectnessTests: XCTestCase {

    var testRepoURL: URL {
        URL(fileURLWithPath: "/tmp/gitstats-edge-case-repo")
    }

    /// Expected total line count at each commit (1-indexed).
    let expectedLineCounts: [Int] = [
        50,   // C1:  5 files × 10 lines
        100,  // C2:  +50 (5 more files)
        105,  // C3:  +5 (append to file1)
        102,  // C4:  -3 (remove from file2)
        102,  // C5:  ±0 (alter file3)
        102,  // C6:  +2-2 (multi-file, net 0)
        102,  // C7:  ±0 (alter file6+file7)
        102,  // C8:  ±0 (rename file8)
        92,   // C9:  -10 (delete file9)
        87,   // C10: -5 (revert file1)
        90,   // C11: +3 (append to file10)
        105,  // C12: +15 (append to file1+file2+file3)
    ]

    // MARK: - Verify repo structure

    func testRepoHas12Commits() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let commits = try await repo.allCommits()
        XCTAssertEqual(commits.count, 12, "Edge-case repo should have exactly 12 commits")
    }

    // MARK: - Core double-counting test: sample ALL commits

    func testNoDoubleCountingFullSample() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 12,  // sample every commit
            granularity: .month
        )

        let buckets = try await engine.analyze(config: config)

        // Group buckets by commit date, compute total line count per commit
        let commitDates = Set(buckets.map(\.commitDate)).sorted()
        XCTAssertEqual(
            commitDates.count, 12,
            "Should have 12 distinct commit dates, got \(commitDates.count)")

        for (i, date) in commitDates.enumerated() {
            let dateBuckets = buckets.filter { $0.commitDate == date }
            let total = dateBuckets.reduce(0) { $0 + $1.lineCount }
            let expected = expectedLineCounts[i]

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            let dateStr = formatter.string(from: date)

            print(
                "  C\(i + 1) [\(dateStr)]: \(total) lines (expected \(expected), buckets: \(dateBuckets.count))"
            )

            XCTAssertEqual(
                total, expected,
                "C\(i + 1) [\(dateStr)]: expected \(expected) lines but got \(total) — double counting detected!"
            )
        }
    }

    // MARK: - No commit should EVER exceed the maximum expected line count

    func testNoCommitExceedsMaxExpected() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 12,
            granularity: .quarter
        )

        let buckets = try await engine.analyze(config: config)
        let maxExpected = expectedLineCounts.max()!

        let commitDates = Set(buckets.map(\.commitDate)).sorted()
        for date in commitDates {
            let total = buckets.filter { $0.commitDate == date }
                .reduce(0) { $0 + $1.lineCount }
            XCTAssertLessThanOrEqual(
                total, maxExpected,
                "Total \(total) exceeds max expected \(maxExpected) at \(date) — likely double counting"
            )
        }
    }

    // MARK: - Same-day commits should be distinct snapshots

    func testSameDayCommitsAreDistinct() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 12,
            granularity: .month
        )

        let buckets = try await engine.analyze(config: config)
        let commitDates = Set(buckets.map(\.commitDate)).sorted()

        // C3 (2023-03-10 10:00) and C4 (2023-03-10 15:00) are same-day
        // C6 (2023-05-15 10:00) and C7 (2023-05-15 18:00) are same-day
        // C10 (2023-08-10 10:00) and C11 (2023-08-10 14:00) are same-day
        // All should be separate entries with correct line counts
        XCTAssertEqual(
            commitDates.count, 12,
            "All 12 commits should be distinct — same-day commits must not merge")
    }

    // MARK: - Line count never negative

    func testNoNegativeLineCounts() async throws {
        let repo = try GitRepository(path: testRepoURL)
        let engine = AnalysisEngine(repo: repo)
        let config = AnalysisConfig(
            sampleCount: 12,
            granularity: .month
        )

        let buckets = try await engine.analyze(config: config)
        for bucket in buckets {
            XCTAssertGreaterThanOrEqual(
                bucket.lineCount, 0,
                "Bucket for \(bucket.filePath) at \(bucket.commitDate) has negative line count: \(bucket.lineCount)"
            )
        }
    }

    // MARK: - Different granularities shouldn't affect totals

    func testDifferentGranularitiesProduceSameTotals() async throws {
        let repo = try GitRepository(path: testRepoURL)

        let granularities: [AnalysisConfig.TimeGranularity] = [.year, .quarter, .month, .week, .day]
        var totalsByGranularity: [String: [Int]] = [:]

        for gran in granularities {
            let engine = AnalysisEngine(repo: repo)
            let config = AnalysisConfig(sampleCount: 12, granularity: gran)
            let buckets = try await engine.analyze(config: config)

            let commitDates = Set(buckets.map(\.commitDate)).sorted()
            let totals = commitDates.map { date in
                buckets.filter { $0.commitDate == date }.reduce(0) { $0 + $1.lineCount }
            }
            totalsByGranularity[gran.rawValue] = totals
        }

        // All granularities should produce the same per-commit totals
        let referenceKey = granularities[0].rawValue
        let referenceTotals = totalsByGranularity[referenceKey]!
        for gran in granularities.dropFirst() {
            let totals = totalsByGranularity[gran.rawValue]!
            XCTAssertEqual(
                totals, referenceTotals,
                "\(gran.rawValue) granularity has different totals than \(referenceKey)"
            )
        }
    }
}
