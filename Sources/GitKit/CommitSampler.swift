import Foundation

/// Samples commits evenly across git history.
public struct CommitSampler {
    
    /// Samples up to `count` commits evenly distributed from the given array.
    /// Always includes the first and last commit.
    public static func sample(_ commits: [GitCommit], count: Int) -> [GitCommit] {
        guard commits.count > count, count >= 2 else {
            return commits
        }
        
        let step = Double(commits.count - 1) / Double(count - 1)
        var indices: [Int] = []
        for i in 0..<count {
            indices.append(Int(Double(i) * step))
        }
        // Ensure last commit is always included
        indices[count - 1] = commits.count - 1
        
        return indices.map { commits[$0] }
    }
    
    /// Refines a set of sampled commits by binary-searching for exact pom.xml
    /// version transition commits between each adjacent pair.
    ///
    /// Algorithm:
    /// 1. Read the pom.xml major.minor version at each sampled commit
    /// 2. For each adjacent pair where the version differs, binary search
    ///    through all commits between them to find the exact transition commit
    /// 3. Return the union of original samples + transition commits, sorted
    ///
    /// - Parameters:
    ///   - sampled: The initial evenly-sampled commits (indices into allCommits)
    ///   - allCommits: The full ordered commit list
    ///   - versionAt: Closure that reads pom.xml major.minor at a commit hash
    /// - Returns: Enriched sample including version transition commits
    public static func refineWithVersionTransitions(
        sampled: [GitCommit],
        allCommits: [GitCommit],
        versionAt: (String) -> String?
    ) -> [GitCommit] {
        guard sampled.count >= 2 else { return sampled }
        
        // Build index lookup for O(1) position finding
        var hashToIndex: [String: Int] = [:]
        for (i, c) in allCommits.enumerated() {
            hashToIndex[c.hash] = i
        }
        
        // Read versions at each sampled commit
        let versions: [String?] = sampled.map { versionAt($0.hash) }
        
        // Collect all indices to include
        var resultIndices = Set<Int>()
        for s in sampled {
            if let idx = hashToIndex[s.hash] {
                resultIndices.insert(idx)
            }
        }
        
        // Binary search between adjacent samples where version changed
        for i in 0..<(sampled.count - 1) {
            guard let vA = versions[i], let vB = versions[i + 1], vA != vB else { continue }
            guard let idxA = hashToIndex[sampled[i].hash],
                  let idxB = hashToIndex[sampled[i + 1].hash],
                  idxB > idxA + 1 else { continue }
            
            // Binary search: find the first commit in (idxA..idxB] where version != vA
            var lo = idxA + 1
            var hi = idxB
            
            while lo < hi {
                let mid = lo + (hi - lo) / 2
                let midVersion = versionAt(allCommits[mid].hash)
                if midVersion == vA {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            
            // lo is the first commit with the new version
            resultIndices.insert(lo)
            // Also include the commit just before the transition
            if lo > 0 {
                resultIndices.insert(lo - 1)
            }
        }
        
        return resultIndices.sorted().map { allCommits[$0] }
    }
}
