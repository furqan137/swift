import Foundation
import CoreML

/// Encodes three variants of a query and averages them for better recall:
///   1. raw query
///   2. "a photo of {query}"
///   3. "a picture of {query}"
/// The averaged vector is L2-normalized before return.
struct PromptEnsembler {

    private let textEncoder: TextEncoder

    init(textEncoder: TextEncoder) {
        self.textEncoder = textEncoder
    }

    /// Encode the query with three-variant ensembling.
    /// Returns a 512-dim L2-normalized [Float] vector.
    func encode(query: String) throws -> [Float] {
        let prompts = [
            query,
            "a photo of \(query)",
            "a picture of \(query)"
        ]

        let dim = CLIPConfig.embeddingDimension
        var sum = [Float](repeating: 0, count: dim)

        for prompt in prompts {
            let shaped = try textEncoder.computeTextEmbedding(prompt: prompt)
            shaped.withUnsafeShapedBufferPointer { ptr, _, _ in
                let count = min(ptr.count, dim)
                for i in 0..<count {
                    sum[i] += ptr[i]
                }
            }
        }

        // Average
        let n = Float(prompts.count)
        for i in 0..<dim { sum[i] /= n }

        // L2-normalize
        var sumSq: Float = 0
        for v in sum { sumSq += v * v }
        let mag = sqrtf(sumSq)
        if mag > 1e-9 {
            for i in 0..<dim { sum[i] /= mag }
        }

        return sum
    }
}
