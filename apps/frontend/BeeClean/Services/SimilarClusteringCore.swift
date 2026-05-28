import Foundation

// MARK: - Hamming Distance
/// Computes the Hamming distance between two 64-bit hashes.
/// Returns the number of differing bits (0-64).
func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
    return (a ^ b).nonzeroBitCount
}

// MARK: - Union-Find (Disjoint Set Union)
/// Efficient data structure for grouping elements into clusters.
/// Uses path compression and union by rank for near O(1) operations.
struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]
    private let count: Int

    /// Initialize with n elements (0..<n)
    init(_ n: Int) {
        self.count = n
        self.parent = Array(0..<n)
        self.rank = Array(repeating: 0, count: n)
    }

    /// Find the root of element x with path compression
    mutating func find(_ x: Int) -> Int {
        guard x >= 0 && x < count else { return x }

        if parent[x] != x {
            parent[x] = find(parent[x])
        }
        return parent[x]
    }

    /// Union two elements into the same set
    /// Returns true if they were in different sets (union performed)
    @discardableResult
    mutating func union(_ a: Int, _ b: Int) -> Bool {
        let rootA = find(a)
        let rootB = find(b)

        if rootA == rootB {
            return false
        }

        // Union by rank
        if rank[rootA] < rank[rootB] {
            parent[rootA] = rootB
        } else if rank[rootA] > rank[rootB] {
            parent[rootB] = rootA
        } else {
            parent[rootB] = rootA
            rank[rootA] += 1
        }

        return true
    }

    /// Check if two elements are in the same set
    mutating func connected(_ a: Int, _ b: Int) -> Bool {
        return find(a) == find(b)
    }

    /// Returns all components as groups of indices
    /// Only returns groups with more than one element
    mutating func components() -> [[Int]] {
        var groups: [Int: [Int]] = [:]

        for i in 0..<count {
            let root = find(i)
            groups[root, default: []].append(i)
        }

        // Filter to only groups with 2+ members
        return groups.values.filter { $0.count > 1 }
    }

    /// Returns all components including singletons
    mutating func allComponents() -> [[Int]] {
        var groups: [Int: [Int]] = [:]

        for i in 0..<count {
            let root = find(i)
            groups[root, default: []].append(i)
        }

        return Array(groups.values)
    }
}

// Real clustering lives in `SimilarClusteringService.clusterBucket(...)`.
// The old top-level `SimilarityClusterer.cluster` / `clusterOptimized`
// helpers were removed: `cluster` was dead code and `clusterOptimized`
// relied on sorting hashes numerically, which is NOT a valid locality-
// sensitive ordering for Hamming distance (flipping the high bit moves a
// value by 2^63 but only 1 Hamming unit). Using the sliding-window
// version would have silently missed real duplicates.
