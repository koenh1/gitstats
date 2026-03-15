import Foundation

/// Handles `git blame` operations to determine when each line in a file was authored.
public struct GitBlame: Sendable {
    
    /// Per-line blame information: who last modified the line and when.
    public struct BlameLine: Sendable {
        public let timestamp: TimeInterval
        public let author: String
    }
    
    /// Regex pattern to extract Unix timestamp from git blame -t output.
    /// Format: <hash> (<author> <timestamp> <tz> <line>) <content>
  private static let timestampPattern: Regex<(Substring, Substring)> = try! .init(
    #"\(.*?\s+(\d{10})\s+[+-]\d{4}\s+\d+\)"#
    )
    
    /// Runs `git blame -t` on a file at a specific commit and returns the Unix timestamps
    /// for each line, indicating when that line was originally authored.
    public static func lineTimestamps(
        repoPath: URL,
        commitHash: String,
        filePath: String
    ) throws -> [TimeInterval] {
        let data = try runBlame(repoPath: repoPath, commitHash: commitHash, filePath: filePath)
        guard let data else { return [] }
        return parseTimeInterValsFast(data: data)
    }
    
    /// Runs `git blame -t` and returns per-line (timestamp, author) pairs.
    public static func lineInfo(
        repoPath: URL,
        commitHash: String,
        filePath: String
    ) throws -> [BlameLine] {
        let data = try runBlame(repoPath: repoPath, commitHash: commitHash, filePath: filePath)
        guard let data else { return [] }
        return parseBlameLinesFast(data: data)
    }
    
    /// Runs git blame and returns raw output data, or nil on failure.
    private static func runBlame(
        repoPath: URL,
        commitHash: String,
        filePath: String
    ) throws -> Data? {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
      process.arguments = ["blame", "-t", commitHash, "--", filePath]
      process.currentDirectoryURL = repoPath
      print(process.arguments!)
      
      let pipe = Pipe()
      process.standardOutput = pipe
      let errPipe = Pipe()
      process.standardError = errPipe
      try process.run()
      
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      
      guard process.terminationStatus == 0 else {
        return nil
      }
      return data
    }
  
  static func parseTimeInterVals(data: Data) -> [TimeInterval] {
        let output = String(decoding: data, as: UTF8.self)
        var timestamps: [TimeInterval] = []
        for line in output.split(separator: "\n", omittingEmptySubsequences: false) {
            if let match = try? timestampPattern.firstMatch(in: line) {
                if let ts = TimeInterval(match.1) {
                    timestamps.append(ts)
                }
            }
        }
        return timestamps
    }
    
    /// Zero-allocation byte-level parser. Scans raw UTF-8 for the pattern:
    ///   ` <10 digits> <+/-> <4 digits> `
    /// and extracts the 10-digit timestamp directly via arithmetic.
    static func parseTimeInterValsFast(data: Data) -> [TimeInterval] {
        // ASCII constants
        let newline: UInt8 = 0x0A  // \n
        let space: UInt8   = 0x20
        let plus: UInt8    = 0x2B  // +
        let minus: UInt8   = 0x2D  // -
        let zero: UInt8    = 0x30  // '0'
        let nine: UInt8    = 0x39  // '9'
        
        return data.withUnsafeBytes { buffer -> [TimeInterval] in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return []
            }
            let count = buffer.count
            
            // Pre-count newlines for capacity hint
            var lineCount = 1
            for i in 0..<count where base[i] == newline { lineCount += 1 }
            var timestamps: [TimeInterval] = []
            timestamps.reserveCapacity(lineCount)
            
            var i = 0
            while i < count {
                // Find the opening '(' — timestamp is always inside parens
                while i < count && base[i] != 0x28 { i += 1 } // '('
                guard i < count else { break }
                i += 1 // skip '('
                
                // Inside the parens, find: <spaces><10-digit-ts><space><+/-><4digits><space><linenum>)
                // Strategy: scan for a space followed by exactly 10 digits followed by space, +/-, 4 digits
                var found = false
                while i < count && base[i] != newline && !found {
                    // Look for space followed by digit
                    if base[i] == space && i + 11 < count && base[i + 1] >= zero && base[i + 1] <= nine {
                        // Check if we have exactly 10 digits followed by space then +/-
                        let tsStart = i + 1
                        var allDigits = true
                        var digitEnd = tsStart
                        while digitEnd < count && digitEnd - tsStart < 10 {
                            if base[digitEnd] < zero || base[digitEnd] > nine {
                                allDigits = false
                                break
                            }
                            digitEnd += 1
                        }
                        
                        if allDigits && digitEnd - tsStart == 10 &&
                           digitEnd < count && base[digitEnd] == space &&
                           digitEnd + 1 < count && (base[digitEnd + 1] == plus || base[digitEnd + 1] == minus) {
                            // Parse 10 digits directly into TimeInterval
                            var ts: TimeInterval = 0
                            for j in tsStart..<digitEnd {
                                ts = ts * 10 + TimeInterval(base[j] - zero)
                            }
                            timestamps.append(ts)
                            found = true
                        }
                    }
                    i += 1
                }
                
                // Skip to next line
                while i < count && base[i] != newline { i += 1 }
                i += 1
            }
            
            return timestamps
        }
    }
    
    /// Zero-allocation byte-level parser that extracts both author and timestamp.
    /// Format: `<hash> (<author> <10-digit-ts> <tz> <linenum>) <content>`
    /// The author is everything between '(' and the last space before the timestamp.
    static func parseBlameLinesFast(data: Data) -> [BlameLine] {
        let newline: UInt8 = 0x0A
        let space: UInt8   = 0x20
        let plus: UInt8    = 0x2B
        let minus: UInt8   = 0x2D
        let zero: UInt8    = 0x30
        let nine: UInt8    = 0x39
        let openParen: UInt8 = 0x28
        
        return data.withUnsafeBytes { buffer -> [BlameLine] in
            guard let base = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return []
            }
            let count = buffer.count
            
            var lineCount = 1
            for i in 0..<count where base[i] == newline { lineCount += 1 }
          print("lines: \(lineCount)")
            var results: [BlameLine] = []
            results.reserveCapacity(lineCount)
            
            var i = 0
            while i < count {
                // Find '('
                while i < count && base[i] != openParen { i += 1 }
                guard i < count else { break }
                let parenStart = i + 1  // start of author name
                i += 1
                
                // Scan for the 10-digit timestamp pattern
                var found = false
                while i < count && base[i] != newline && !found {
                    if base[i] == space && i + 11 < count && base[i + 1] >= zero && base[i + 1] <= nine {
                        let tsStart = i + 1
                        var allDigits = true
                        var digitEnd = tsStart
                        while digitEnd < count && digitEnd - tsStart < 10 {
                            if base[digitEnd] < zero || base[digitEnd] > nine {
                                allDigits = false
                                break
                            }
                            digitEnd += 1
                        }
                        
                        if allDigits && digitEnd - tsStart == 10 &&
                           digitEnd < count && base[digitEnd] == space &&
                           digitEnd + 1 < count && (base[digitEnd + 1] == plus || base[digitEnd + 1] == minus) {
                            // Parse timestamp
                            var ts: TimeInterval = 0
                            for j in tsStart..<digitEnd {
                                ts = ts * 10 + TimeInterval(base[j] - zero)
                            }
                            
                            // Extract author: from parenStart to the space before timestamp
                            // Trim trailing spaces
                            var authorEnd = i
                            while authorEnd > parenStart && base[authorEnd - 1] == space {
                                authorEnd -= 1
                            }
                            let authorBytes = Data(bytes: base + parenStart, count: authorEnd - parenStart)
                            let author = String(decoding: authorBytes, as: UTF8.self)
                            
                            results.append(BlameLine(timestamp: ts, author: AuthorNormalizer.normalize(author)))
                            found = true
                        }
                    }
                    i += 1
                }
                
                // Skip to next line
                while i < count && base[i] != newline { i += 1 }
                i += 1
            }
            
            return results
        }
    }
}
