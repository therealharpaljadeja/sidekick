import Foundation
import NaturalLanguage

public enum ChecklistParser {
    /// One item per non-empty line; bullets, numbering and `[ ]` boxes are stripped.
    public static func items(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            var item = line.trimmingCharacters(in: .whitespaces)
            let markers = ["- [ ]", "- [x]", "* [ ]", "* [x]", "[ ]", "[x]", "-", "*", "•", "–", "—"]
            if let marker = markers.first(where: { item.lowercased().hasPrefix($0) }) {
                item = String(item.dropFirst(marker.count))
            } else if let number = item.range(of: #"^\d+[.)]"#, options: .regularExpression) {
                item = String(item[number.upperBound...])
            }
            item = item.trimmingCharacters(in: .whitespaces)
            return item.isEmpty ? nil : item
        }
    }
}

/// Offline fallback for deciding whether speech covers a checklist item: the item's key words
/// (lemmatized, so "recordings" matches "recording") must show up in what was said.
public enum TopicMatcher {
    /// Words that describe the act of presenting rather than the topic.
    private static let ignored: Set<String> = [
        "show", "demo", "demonstrate", "talk", "explain", "mention", "cover", "introduce", "present",
        "walk", "go", "do", "use", "try", "let", "make", "get", "see", "look", "how", "what", "why",
        "when", "where", "about", "thing", "part", "quick", "quickly", "briefly", "first", "next",
        "then", "finally", "last", "also", "new", "way", "our", "my", "your", "the", "and", "with",
        "through", "into", "from", "this", "that", "these", "those", "be", "have", "can", "will",
    ]

    public static func keywords(for item: String) -> [String] {
        var seen = Set<String>()
        return lemmas(in: item, contentOnly: true).filter { !ignored.contains($0) && seen.insert($0).inserted }
    }

    public static func lemmas(in text: String, contentOnly: Bool = false) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        let content: Set<NLTag> = [.noun, .verb, .adjective, .adverb, .otherWord, .number]
        var result: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther]) { lemma, range in
            if contentOnly, let kind = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass).0,
               !content.contains(kind) { return true }
            let word = ScriptParser.normalize((lemma?.rawValue).flatMap { $0.isEmpty ? nil : $0 } ?? String(text[range]))
            if word.count >= 2 { result.append(word) }
            return true
        }
        return result
    }

    /// With `strict`, every key word must be heard; otherwise most of them.
    public static func covers(keywords: [String], spoken: [String], strict: Bool = false) -> Bool {
        guard !keywords.isEmpty else { return false }
        let heard = heardCount(keywords: keywords, spoken: spoken)
        if strict { return heard == keywords.count }
        if keywords.count <= 2 { return heard == keywords.count }
        return heard >= 2 && Double(heard) >= Double(keywords.count) * 0.6
    }

    static func isMatch(_ a: String, _ b: String) -> Bool {
        a == b || (a.count >= 5 && b.count >= 5 && a.prefix(5) == b.prefix(5))
    }
}
