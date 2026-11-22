import Foundation

/// One spoken unit of the script: what is shown, and the normalized key used for matching.
public struct ScriptToken: Equatable, Sendable {
    public let text: String
    public let key: String
    public let trailingSpace: Bool
    public let endsSentence: Bool

    public var displayText: String { trailingSpace ? text + " " : text }
}

public enum ScriptParser {
    private static let joiners: Set<Character> = ["-", "–", "—", "/"]
    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…", ":"]
    private static let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]"]

    public static func tokenize(_ script: String) -> [ScriptToken] {
        var tokens: [ScriptToken] = []
        var pendingPrefix = ""

        for chunk in script.split(whereSeparator: \.isWhitespace) {
            var parts: [String] = []
            var current = ""
            for ch in chunk {
                current.append(ch)
                if joiners.contains(ch) {
                    parts.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { parts.append(current) }

            for (index, part) in parts.enumerated() {
                let isLast = index == parts.count - 1
                let key = normalize(part)
                if key.isEmpty {
                    // Punctuation-only fragments ride along with a neighbouring word.
                    if let last = tokens.popLast() {
                        let separator = last.trailingSpace ? " " : ""
                        tokens.append(ScriptToken(
                            text: last.text + separator + part,
                            key: last.key,
                            trailingSpace: isLast,
                            endsSentence: last.endsSentence || endsSentence(part)
                        ))
                    } else {
                        pendingPrefix += part + (isLast ? " " : "")
                    }
                    continue
                }
                tokens.append(ScriptToken(
                    text: pendingPrefix + part,
                    key: key,
                    trailingSpace: isLast,
                    endsSentence: endsSentence(part)
                ))
                pendingPrefix = ""
            }
        }
        return tokens
    }

    public static func normalize(_ word: String) -> String {
        let folded = word
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: "%", with: "percent")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func endsSentence(_ part: String) -> Bool {
        var trimmed = Substring(part)
        while let last = trimmed.last, closers.contains(last) { trimmed = trimmed.dropLast() }
        guard let last = trimmed.last else { return false }
        return sentenceEnders.contains(last)
    }
}

/// Aligns recognized speech against the script and decides how far the reader has got.
public struct ScriptFollower: Sendable {
    public let tokens: [ScriptToken]
    /// How many upcoming words a single recognized word may jump to.
    public var lookahead = 8
    /// How far ahead a run of three matching words may re-sync the cursor (e.g. after skipping a sentence).
    public var resyncWindow = 40

    public init(tokens: [ScriptToken]) {
        self.tokens = tokens
    }

    /// Returns the new cursor (index of the next word to say) after hearing `spoken`, starting at `start`.
    public func advance(from start: Int, spoken: [String]) -> Int {
        var cursor = min(max(start, 0), tokens.count)
        var recent: [String] = []

        for raw in spoken {
            for piece in raw.split(whereSeparator: \.isWhitespace) {
                let word = ScriptParser.normalize(String(piece))
                guard !word.isEmpty else { continue }
                recent.append(word)
                if recent.count > 3 { recent.removeFirst() }
                guard cursor < tokens.count else { return cursor }

                if let hit = nearbyMatch(for: word, from: cursor) {
                    cursor = hit + 1
                } else if recent.count == 3, let hit = sequenceMatch(for: recent, from: cursor) {
                    cursor = hit + 1
                }
            }
        }
        return cursor
    }

    func nearbyMatch(for word: String, from cursor: Int) -> Int? {
        let end = min(tokens.count, cursor + lookahead)
        guard cursor < end else { return nil }
        for index in cursor..<end where Self.isMatch(tokens[index].key, word) {
            let skipped = index - cursor
            if skipped == 0 { return index }
            if Self.stopwords.contains(word) { continue }
            if skipped <= 2 || word.count >= 5 { return index }
        }
        return nil
    }

    func sequenceMatch(for recent: [String], from cursor: Int) -> Int? {
        guard recent.contains(where: { !Self.stopwords.contains($0) }) else { return nil }
        let end = min(tokens.count, cursor + resyncWindow)
        var index = cursor + 2
        while index < end {
            if Self.isMatch(tokens[index - 2].key, recent[0]),
               Self.isMatch(tokens[index - 1].key, recent[1]),
               Self.isMatch(tokens[index].key, recent[2]) {
                return index
            }
            index += 1
        }
        return nil
    }

    /// Index of the first word of the sentence after the one containing `cursor`.
    public func nextSentence(after cursor: Int) -> Int {
        var index = max(cursor, 0)
        while index < tokens.count {
            if tokens[index].endsSentence { return index + 1 }
            index += 1
        }
        return tokens.count
    }

    /// Index of the first word of the sentence before `cursor` (or the start of the current one).
    public func previousSentence(before cursor: Int) -> Int {
        var index = min(cursor, tokens.count) - 2
        while index >= 0 {
            if tokens[index].endsSentence { return index + 1 }
            index -= 1
        }
        return 0
    }

    public static func isMatch(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        let longer = max(a.count, b.count)
        if shorter >= 4, longer - shorter <= 3, a.hasPrefix(b) || b.hasPrefix(a) { return true }
        if longer >= 8 { return levenshtein(a, b, limit: 2) <= 2 }
        if longer >= 5 { return levenshtein(a, b, limit: 1) <= 1 }
        return false
    }

    static func levenshtein(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        if abs(a.count - b.count) > limit { return limit + 1 }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            current[0] = i
            var rowMin = current[0]
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    static let stopwords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "so", "to", "of", "in", "on", "at", "for", "with", "by",
        "is", "are", "was", "were", "be", "been", "it", "its", "this", "that", "these", "those", "i",
        "you", "we", "they", "he", "she", "me", "my", "your", "our", "their", "as", "if", "then", "than",
        "do", "does", "did", "not", "no", "yes", "can", "will", "just", "up", "out", "what", "how",
        "here", "there", "now", "all", "im", "its", "thats", "lets", "dont", "from", "into", "about",
    ]
}

public enum Utterance {
    /// After a pause the recognizer can restart its partial transcript with only the new words,
    /// without a final result. Tell that apart from a revision of the same words, such as a
    /// dropped leading filler, so the caller can reset its per-segment word count.
    public static func isNew(_ words: [String], after previous: [String]) -> Bool {
        guard words.count < previous.count, let first = words.first?.lowercased(),
              let previousFirst = previous.first?.lowercased() else { return false }
        let new = words.map { $0.lowercased() }, old = previous.map { $0.lowercased() }
        if first != previousFirst, (1...2).contains(where: { old.dropFirst($0).starts(with: new) }) {
            return false
        }
        return first != previousFirst || words.count <= previous.count / 2
    }
}
