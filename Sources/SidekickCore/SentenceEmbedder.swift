import CoreML
import Foundation

/// Splits text into BERT word pieces, the way the bundled sentence model was trained.
public struct WordPieceTokenizer: Sendable {
    private let ids: [String: Int32]
    public let maxLength: Int

    public init(vocabulary: URL, maxLength: Int = 64) throws {
        let lines = try String(contentsOf: vocabulary, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        var ids: [String: Int32] = [:]
        for (index, line) in lines.enumerated() where !line.isEmpty { ids[String(line)] = Int32(index) }
        self.ids = ids
        self.maxLength = maxLength
    }

    /// Token ids with `[CLS]` and `[SEP]`, padded to `maxLength`, and the matching attention mask.
    public func encode(_ text: String) -> (ids: [Int32], mask: [Int32]) {
        let cls = ids["[CLS]"] ?? 101, sep = ids["[SEP]"] ?? 102, unk = ids["[UNK]"] ?? 100
        var tokens: [Int32] = [cls]
        for word in Self.basicWords(text) {
            tokens += pieces(of: word) ?? [unk]
            if tokens.count >= maxLength - 1 { break }
        }
        tokens = Array(tokens.prefix(maxLength - 1)) + [sep]
        let mask = [Int32](repeating: 1, count: tokens.count) + [Int32](repeating: 0, count: maxLength - tokens.count)
        return (tokens + [Int32](repeating: 0, count: maxLength - tokens.count), mask)
    }

    private func pieces(of word: String) -> [Int32]? {
        let characters = Array(word)
        guard characters.count <= 100 else { return nil }
        var result: [Int32] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var match: Int32?
            while start < end {
                let piece = (start > 0 ? "##" : "") + String(characters[start..<end])
                if let id = ids[piece] { match = id; break }
                end -= 1
            }
            guard let match else { return nil }
            result.append(match)
            start = end
        }
        return result
    }

    /// Lowercases, strips accents and splits on spaces and punctuation, like BERT's basic tokenizer.
    static func basicWords(_ text: String) -> [String] {
        let folded = text.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { $0.properties.generalCategory != .nonspacingMark }
        var words: [String] = []
        var current = ""
        for scalar in folded {
            if scalar.properties.isWhitespace {
                if !current.isEmpty { words.append(current); current = "" }
            } else if CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar) {
                if !current.isEmpty { words.append(current); current = "" }
                words.append(String(scalar))
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}

/// Turns a sentence into a unit-length meaning vector with a small on-device model (bge-small-en-v1.5),
/// so sentences about the same thing score close together even with different words.
public final class SentenceEmbedder: @unchecked Sendable {
    private let model: MLModel
    private let tokenizer: WordPieceTokenizer
    private let lock = NSLock()

    public init(model: URL, vocabulary: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        self.model = try MLModel(contentsOf: model, configuration: configuration)
        self.tokenizer = try WordPieceTokenizer(vocabulary: vocabulary)
    }

    public func embed(_ text: String) throws -> [Float] {
        let (ids, mask) = tokenizer.encode(text)
        let shape = [1, NSNumber(value: tokenizer.maxLength)]
        let idArray = try MLMultiArray(shape: shape, dataType: .int32)
        let maskArray = try MLMultiArray(shape: shape, dataType: .int32)
        for index in 0..<tokenizer.maxLength {
            idArray[index] = NSNumber(value: ids[index])
            maskArray[index] = NSNumber(value: mask[index])
        }
        let input = try MLDictionaryFeatureProvider(dictionary: ["input_ids": idArray, "attention_mask": maskArray])
        lock.lock(); defer { lock.unlock() }
        guard let output = try model.prediction(from: input).featureValue(for: "embedding")?.multiArrayValue else { return [] }
        return (0..<output.count).map { output[$0].floatValue }
    }

    public static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        for index in a.indices { dot += a[index] * b[index] }
        return dot
    }
}
