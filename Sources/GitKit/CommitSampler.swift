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
}
