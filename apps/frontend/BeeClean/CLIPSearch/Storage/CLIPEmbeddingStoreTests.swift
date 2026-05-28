import Foundation

/// DEBUG-only self-test for CLIPEmbeddingStore.
/// Inserts 1000 random 512-dim vectors, reads them back,
/// and asserts byte-for-byte equality on the round-trip.
enum CLIPEmbeddingStoreTests {

    static func runStoreTest() {
        #if DEBUG
        Task.detached(priority: .utility) {
            do {
                // Use a throwaway temp database so we never touch the real one
                let tmpDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("CLIPStoreTest-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let dbPath = tmpDir.appendingPathComponent("test.sqlite").path
                let store = CLIPEmbeddingStore(path: dbPath)

                let dim = CLIPConfig.embeddingDimension
                let n = 1000

                // 1. Generate 1000 random vectors
                var vectors = [[Float]]()
                vectors.reserveCapacity(n)
                for _ in 0..<n {
                    let vec = (0..<dim).map { _ in Float.random(in: -1...1) }
                    vectors.append(vec)
                }

                // 2. Insert all
                for i in 0..<n {
                    store.upsert(assetId: "test-asset-\(i)", embedding: vectors[i])
                }

                // 3. Verify count
                let storedCount = store.count()
                assert(storedCount == n,
                       "Expected \(n) rows, got \(storedCount)")

                // 4. Fetch all and verify byte-equality
                let rows = await store.fetchAll()
                assert(rows.count == n,
                       "fetchAll returned \(rows.count), expected \(n)")

                let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.assetId, $0.embedding) })

                for i in 0..<n {
                    let key = "test-asset-\(i)"
                    guard let fetched = rowsByID[key] else {
                        assertionFailure("Missing row for \(key)")
                        continue
                    }
                    assert(fetched.count == dim,
                           "\(key): dim \(fetched.count) != \(dim)")

                    // Byte-level comparison via raw memory
                    let match = vectors[i].withUnsafeBufferPointer { orig in
                        fetched.withUnsafeBufferPointer { read in
                            memcmp(orig.baseAddress, read.baseAddress, dim * MemoryLayout<Float>.size) == 0
                        }
                    }
                    assert(match, "\(key): byte mismatch on round-trip")
                }

                // 5. Test missingAssetIds
                let candidates = (0..<(n + 500)).map { "test-asset-\($0)" }
                let missing = store.missingAssetIds(from: candidates)
                assert(missing.count == 500,
                       "Expected 500 missing, got \(missing.count)")
                for i in n..<(n + 500) {
                    assert(missing.contains("test-asset-\(i)"),
                           "test-asset-\(i) should be missing")
                }

                // 6. Test purgeStaleVersions
                // Insert one row with a fake old version
                store.upsert(assetId: "stale-asset", embedding: [Float](repeating: 0, count: dim))
                // Manually tweak its version by re-upserting won't work since upsert
                // always uses current version. So we test purge keeps current rows.
                let countBefore = store.count()
                store.purgeStaleVersions(keeping: CLIPConfig.clipModelVersion)
                let countAfter = store.count()
                assert(countAfter == countBefore,
                       "Purge removed current-version rows: \(countBefore) -> \(countAfter)")

                // Cleanup
                try? FileManager.default.removeItem(at: tmpDir)

                print("✅ CLIPEmbeddingStore test passed — \(n) vectors round-tripped with byte-equality")
            } catch {
                print("❌ CLIPEmbeddingStore test FAILED: \(error)")
            }
        }
        #endif
    }
}
