// For licensing see accompanying LICENSE.md file.
// Copyright (C) 2022 Apple Inc. All Rights Reserved.

import Foundation
import CoreML

///  A model for encoding text
public struct TextEncoder {

    /// Text tokenizer
    var tokenizer: BPETokenizer

    /// Embedding model
    var model: MLModel

    init(resourcesAt baseURL: URL) throws {
        // Prefer Bundle resource lookup over raw path construction
        let textEncoderURL: URL
        if let bundleURL = Bundle.main.url(forResource: "TextEncoder_mobileCLIP_s2", withExtension: "mlmodelc") {
            textEncoderURL = bundleURL
        } else {
            textEncoderURL = baseURL.appending(path: "TextEncoder_mobileCLIP_s2.mlmodelc")
        }
        let vocabURL = baseURL.appending(path: "vocab.json")
        let mergesURL = baseURL.appending(path: "merges.txt")

        // Text tokenizer and encoder
        let tokenizer = try BPETokenizer(mergesAt: mergesURL, vocabularyAt: vocabURL)

        #if targetEnvironment(simulator)
        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly
        let textEncoderModel = try MLModel(contentsOf: textEncoderURL, configuration: config)
        #else
        // On device, try .all first with fallback through .cpuAndGPU → .cpuOnly
        let textEncoderModel = try Self.loadWithFallback(url: textEncoderURL)
        #endif

        self.tokenizer = tokenizer
        self.model = textEncoderModel
    }

    /// Try loading the model with progressively simpler compute unit configs.
    private static func loadWithFallback(url: URL) throws -> MLModel {
        let unitOptions: [MLComputeUnits] = [.all, .cpuAndGPU, .cpuOnly]
        var lastError: Error?
        for units in unitOptions {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = units
                let model = try MLModel(contentsOf: url, configuration: config)
                if units != .all {
                    print("[TextEncoder] Loaded with fallback compute units: \(units.rawValue)")
                }
                return model
            } catch {
                print("[TextEncoder] Failed with \(units.rawValue): \(error.localizedDescription)")
                lastError = error
            }
        }
        throw lastError ?? NSError(domain: "TextEncoder", code: -1, userInfo: [NSLocalizedDescriptionKey: "All compute unit configs failed"])
    }
    
    public func computeTextEmbedding(prompt: String) throws -> MLShapedArray<Float32> {
        let raw = try self.encode(prompt)
        return Self.l2Normalize(raw)
    }
    
    /**
    /// Creates text encoder which embeds a tokenized string
    ///
    /// - Parameters:
    ///   - tokenizer: Tokenizer for input text
    ///   - model: Model for encoding tokenized text
    public init(tokenizer: BPETokenizer, model: MLModel) {
        self.tokenizer = tokenizer
        self.model = model
    }
     */

    /// Encode input text/string
    ///
    ///  - Parameters:
    ///     - text: Input text to be tokenized and then embedded
    ///  - Returns: Embedding representing the input text
    private func encode(_ text: String) throws -> MLShapedArray<Float32> {

        // Get models expected input length
        let inputLength = inputShape.last!

        // Tokenize, padding to the expected length
        var (tokens, ids) = tokenizer.tokenize(input: text, minCount: inputLength)

        // Truncate if necessary
        if ids.count > inputLength {
            tokens = tokens.dropLast(tokens.count - inputLength)
            ids = ids.dropLast(ids.count - inputLength)
            let truncated = tokenizer.decode(tokens: tokens)
            print("Needed to truncate input '\(text)' to '\(truncated)'")
        }

        // Use the model to generate the embedding
        return try encode(ids: ids)
    }

    /// Prediction queue
    let queue = DispatchQueue(label: "textencoder.predict")

    func encode(ids: [Int]) throws -> MLShapedArray<Float32> {
        let inputName = inputDescription.name
        let inputShape = inputShape

        let floatIds = ids.map { Float32($0) }
        let inputArray = MLShapedArray<Float32>(scalars: floatIds, shape: inputShape)
        let inputFeatures = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLMultiArray(inputArray)])

        let result = try queue.sync { try model.prediction(from: inputFeatures) }
        guard let multiArray = result.featureValue(for: "text_embeddings")?.multiArrayValue else {
            throw NSError(
                domain: "TextEncoder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Model returned no 'text_embeddings' feature"]
            )
        }
        return MLShapedArray<Float32>(converting: multiArray)
    }

    private static func l2Normalize(_ array: MLShapedArray<Float32>) -> MLShapedArray<Float32> {
        var scalars = array.scalars
        var sumSq: Float = 0
        for v in scalars { sumSq += v * v }
        let mag = sqrtf(sumSq)
        if mag > 1e-9 {
            for i in scalars.indices { scalars[i] /= mag }
        }
        return MLShapedArray<Float32>(scalars: scalars, shape: array.shape)
    }

    var inputDescription: MLFeatureDescription {
        model.modelDescription.inputDescriptionsByName.first!.value
    }

    var inputShape: [Int] {
        inputDescription.multiArrayConstraint!.shape.map { $0.intValue }
    }

}
