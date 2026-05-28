import Foundation
import CoreML
import UIKit

enum CLIPSelfTest {

    // MARK: - Result tracking

    enum SelfTestResult {
        case notRun
        case running
        case passed
        case failed(String)

        var displayText: String {
            switch self {
            case .notRun: return "Not run"
            case .running: return "Running…"
            case .passed: return "Passed"
            case .failed(let msg): return "Failed: \(msg)"
            }
        }
    }

    @MainActor static var lastResult: SelfTestResult = .notRun

    static func runSelfTest() {
        Task { @MainActor in lastResult = .running }
        Task.detached(priority: .utility) {
            do {
                let baseURL = Bundle.main.resourceURL!

                // 1. Load both CoreML models
                let imgEncoder = try ImgEncoder(resourcesAt: baseURL)
                let textEncoder = try TextEncoder(resourcesAt: baseURL)
                print("[CLIPSelfTest] Both models loaded")

                // 2. Encode a solid-color test image
                let imageEmbedding = try await imgEncoder.computeImgEmbedding(
                    img: Self.solidColorImage()
                )
                let imgDim = imageEmbedding.shape.last!
                let imgMag = Self.l2Magnitude(imageEmbedding)
                assert(imgDim == CLIPConfig.embeddingDimension,
                       "Image embedding dimension \(imgDim) != \(CLIPConfig.embeddingDimension)")
                assert(abs(imgMag - 1.0) < 0.05,
                       "Image embedding L2 magnitude \(imgMag) not ≈ 1.0")
                print("[CLIPSelfTest] Image encoder OK  dim=\(imgDim) mag=\(imgMag)")

                // 3. Encode a known text string
                let textEmbedding = try textEncoder.computeTextEmbedding(prompt: "a photo of a dog")
                let txtDim = textEmbedding.shape.last!
                let txtMag = Self.l2Magnitude(textEmbedding)
                assert(txtDim == CLIPConfig.embeddingDimension,
                       "Text embedding dimension \(txtDim) != \(CLIPConfig.embeddingDimension)")
                assert(abs(txtMag - 1.0) < 0.05,
                       "Text embedding L2 magnitude \(txtMag) not ≈ 1.0")
                print("[CLIPSelfTest] Text encoder  OK  dim=\(txtDim) mag=\(txtMag)")

                print("✅ CLIP self-test passed")
                await MainActor.run { lastResult = .passed }
            } catch {
                print("❌ CLIP self-test FAILED: \(error)")
                let msg = error.localizedDescription
                await MainActor.run { lastResult = .failed(msg) }
            }
        }
    }

    // MARK: - Helpers

    private static func solidColorImage() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func l2Magnitude(_ array: MLShapedArray<Float32>) -> Float {
        var sumSq: Float = 0
        array.withUnsafeShapedBufferPointer { ptr, _, _ in
            for i in 0..<ptr.count {
                sumSq += ptr[i] * ptr[i]
            }
        }
        return sqrtf(sumSq)
    }
}
