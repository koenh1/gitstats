import XCTest
import Foundation
@testable import GitKit

final class GitBlameParserTests: XCTestCase {
    
    // MARK: - parseTimeInterVals Tests
    
    /// Real git blame -t output for a small file (3 lines).
    func testParseBasicBlameOutput() {
        let blameOutput = """
        a1b2c3d4 (Alice   1700000000 +0100  1) import Foundation
        e5f6a7b8 (Bob     1700100000 -0500  2) 
        a1b2c3d4 (Alice   1700000000 +0100  3) let x = 42
        """
        let data = Data(blameOutput.utf8)
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        
        XCTAssertEqual(timestamps.count, 3)
        XCTAssertEqual(timestamps[0], 1700000000)
        XCTAssertEqual(timestamps[1], 1700100000)
        XCTAssertEqual(timestamps[2], 1700000000)
    }
    
    /// Author names with spaces (e.g. "John Doe").
    func testParseMultiWordAuthor() {
        let blameOutput = """
        abcdef12 (John Doe      1695000000 +0200  1) // comment
        abcdef12 (John Doe      1695000000 +0200  2) func hello() {
        fedcba98 (Jane Smith    1698000000 +0000  3)     print("hi")
        abcdef12 (John Doe      1695000000 +0200  4) }
        """
        let data = Data(blameOutput.utf8)
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        
        XCTAssertEqual(timestamps.count, 4)
        XCTAssertEqual(timestamps[0], 1695000000)
        XCTAssertEqual(timestamps[1], 1695000000)
        XCTAssertEqual(timestamps[2], 1698000000)
        XCTAssertEqual(timestamps[3], 1695000000)
    }
    
    /// Lines with parentheses in the code content (shouldn't confuse the parser).
    func testParseWithParensInContent() {
        let blameOutput = """
        aabbccdd (dev  1690000000 +0000  1) func foo(bar: (Int) -> Void) {
        aabbccdd (dev  1690000000 +0000  2)     bar(42)
        aabbccdd (dev  1690000000 +0000  3) }
        """
        let data = Data(blameOutput.utf8)
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        
        XCTAssertEqual(timestamps.count, 3)
        XCTAssertEqual(timestamps[0], 1690000000)
    }
    
    /// Empty input should produce empty result.
    func testParseEmptyInput() {
        let data = Data()
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        XCTAssertTrue(timestamps.isEmpty)
    }
    
    /// Single line file.
    func testParseSingleLine() {
        let blameOutput = "deadbeef (user 1680000000 +0100  1) hello world\n"
        let data = Data(blameOutput.utf8)
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        
        XCTAssertEqual(timestamps.count, 1)
        XCTAssertEqual(timestamps[0], 1680000000)
    }
    
    /// Negative timezone offset.
    func testParseNegativeTimezone() {
        let blameOutput = "12345678 (dev  1700500000 -0800  1) code\n"
        let data = Data(blameOutput.utf8)
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        
        XCTAssertEqual(timestamps.count, 1)
        XCTAssertEqual(timestamps[0], 1700500000)
    }
    
    /// Lines with long hashes (full 40-char SHA).
    func testParseFullSHA() {
        let blameOutput = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 (user 1700000000 +0000  1) line1\n"
        let data = Data(blameOutput.utf8)
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        
        XCTAssertEqual(timestamps.count, 1)
        XCTAssertEqual(timestamps[0], 1700000000)
    }
    
    /// Boundary commit prefix (^) that git blame uses for lines from the initial commit.
    func testParseBoundaryCommit() {
        let blameOutput = "^abcdef1 (user 1600000000 +0000  1) initial line\n"
        let data = Data(blameOutput.utf8)
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        
        XCTAssertEqual(timestamps.count, 1)
        XCTAssertEqual(timestamps[0], 1600000000)
    }
    
    /// Large file simulation — performance sanity check.
    func testParsePerformanceLargeOutput() {
        let data = Self.generateBlameData(lineCount: 10_000)
        
        let start = CFAbsoluteTimeGetCurrent()
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertEqual(timestamps.count, 10_000)
        XCTAssertEqual(timestamps[0], 1600000000)
        XCTAssertEqual(timestamps[9999], 1600000000 + 9999 * 100)
        
        print("  parseTimeInterVals (10K lines): \(String(format: "%.3f", elapsed))s")
    }
    
    /// 100K lines — benchmark for optimization comparison.
    func testParsePerformance100KLines() {
        let data = Self.generateBlameData(lineCount: 100_000)
        
        let start = CFAbsoluteTimeGetCurrent()
        let timestamps = GitBlame.parseTimeInterVals(data: data)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertEqual(timestamps.count, 100_000)
        
        print("══════════════════════════════════════════")
        print("  parseTimeInterVals (100K lines): \(String(format: "%.3f", elapsed))s")
        print("══════════════════════════════════════════")
    }
    
    // MARK: - parseTimeInterValsFast Correctness
    
    func testFastParseBasicBlameOutput() {
        let blameOutput = """
        a1b2c3d4 (Alice   1700000000 +0100  1) import Foundation
        e5f6a7b8 (Bob     1700100000 -0500  2) 
        a1b2c3d4 (Alice   1700000000 +0100  3) let x = 42
        """
        let data = Data(blameOutput.utf8)
        let fast = GitBlame.parseTimeInterValsFast(data: data)
        let regex = GitBlame.parseTimeInterVals(data: data)
        XCTAssertEqual(fast, regex, "Fast parser should match regex parser")
    }
    
    func testFastParseMultiWordAuthor() {
        let blameOutput = """
        abcdef12 (John Doe      1695000000 +0200  1) // comment
        abcdef12 (John Doe      1695000000 +0200  2) func hello() {
        fedcba98 (Jane Smith    1698000000 +0000  3)     print("hi")
        abcdef12 (John Doe      1695000000 +0200  4) }
        """
        let data = Data(blameOutput.utf8)
        let fast = GitBlame.parseTimeInterValsFast(data: data)
        let regex = GitBlame.parseTimeInterVals(data: data)
        XCTAssertEqual(fast, regex)
    }
    
    func testFastParseWithParensInContent() {
        let blameOutput = """
        aabbccdd (dev  1690000000 +0000  1) func foo(bar: (Int) -> Void) {
        aabbccdd (dev  1690000000 +0000  2)     bar(42)
        aabbccdd (dev  1690000000 +0000  3) }
        """
        let data = Data(blameOutput.utf8)
        let fast = GitBlame.parseTimeInterValsFast(data: data)
        let regex = GitBlame.parseTimeInterVals(data: data)
        XCTAssertEqual(fast, regex)
    }
    
    func testFastParseEmptyInput() {
        let fast = GitBlame.parseTimeInterValsFast(data: Data())
        XCTAssertTrue(fast.isEmpty)
    }
    
    func testFastParseBoundaryCommit() {
        let blameOutput = "^abcdef1 (user 1600000000 +0000  1) initial line\n"
        let data = Data(blameOutput.utf8)
        let fast = GitBlame.parseTimeInterValsFast(data: data)
        let regex = GitBlame.parseTimeInterVals(data: data)
        XCTAssertEqual(fast, regex)
    }
    
    func testFastParseFullSHA() {
        let blameOutput = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 (user 1700000000 +0000  1) line1\n"
        let data = Data(blameOutput.utf8)
        let fast = GitBlame.parseTimeInterValsFast(data: data)
        let regex = GitBlame.parseTimeInterVals(data: data)
        XCTAssertEqual(fast, regex)
    }
    
    // MARK: - Head-to-Head Performance Comparison
    
    func testPerformanceComparison10K() {
        let data = Self.generateBlameData(lineCount: 10_000)
        
        let startRegex = CFAbsoluteTimeGetCurrent()
        let regexResult = GitBlame.parseTimeInterVals(data: data)
        let elapsedRegex = CFAbsoluteTimeGetCurrent() - startRegex
        
        let startFast = CFAbsoluteTimeGetCurrent()
        let fastResult = GitBlame.parseTimeInterValsFast(data: data)
        let elapsedFast = CFAbsoluteTimeGetCurrent() - startFast
        
        XCTAssertEqual(regexResult, fastResult, "Both parsers must produce identical results")
        
        let speedup = elapsedRegex / elapsedFast
        print("══════════════════════════════════════════")
        print("  10K lines:")
        print("    Regex:  \(String(format: "%.3f", elapsedRegex))s")
        print("    Fast:   \(String(format: "%.3f", elapsedFast))s")
        print("    Speedup: \(String(format: "%.1f", speedup))x")
        print("══════════════════════════════════════════")
    }
    
    func testPerformanceComparison100K() {
        let data = Self.generateBlameData(lineCount: 100_000)
        
        let startRegex = CFAbsoluteTimeGetCurrent()
        let regexResult = GitBlame.parseTimeInterVals(data: data)
        let elapsedRegex = CFAbsoluteTimeGetCurrent() - startRegex
        
        let startFast = CFAbsoluteTimeGetCurrent()
        let fastResult = GitBlame.parseTimeInterValsFast(data: data)
        let elapsedFast = CFAbsoluteTimeGetCurrent() - startFast
        
        XCTAssertEqual(regexResult, fastResult, "Both parsers must produce identical results")
        
        let speedup = elapsedRegex / elapsedFast
        print("══════════════════════════════════════════")
        print("  100K lines:")
        print("    Regex:  \(String(format: "%.3f", elapsedRegex))s")
        print("    Fast:   \(String(format: "%.3f", elapsedFast))s")
        print("    Speedup: \(String(format: "%.1f", speedup))x")
        print("══════════════════════════════════════════")
    }
    
    // MARK: - Helpers
    
    private static func generateBlameData(lineCount: Int) -> Data {
        var lines: [String] = []
        lines.reserveCapacity(lineCount)
        for i in 0..<lineCount {
            let ts = 1600000000 + i * 100
            lines.append("abcd1234 (user \(ts) +0000 \(String(format: "%6d", i + 1))) line content here \(i)")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }
}

