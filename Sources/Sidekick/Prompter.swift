import os
import Combine
import Foundation
import SidekickCore

/// Owns the script position and connects speech recognition to it.
@MainActor
final class Prompter: ObservableObject {
    static let shared = Prompter()

    @Published private(set) var tokens: [ScriptToken] = []
    @Published private(set) var cursor = 0
    @Published private(set) var isPresenting = false
    @Published private(set) var isListening = false
    @Published private(set) var mode: PromptMode = .script
    @Published private(set) var items: [String] = []
    @Published private(set) var itemCursor = 0
    /// The item showing its check mark for a moment before it rolls away.
    @Published private(set) var checkingItem: Int?
    @Published var message: String?

    let speech = SpeechFollower()

    private var follower = ScriptFollower(tokens: [])
    private var loadedScript = ""
    private var segmentStart = 0
    private var wordsSeenInSegment = 0
    private var lastWordCount = 0
    private var cancellables = Set<AnyCancellable>()

    private var itemKeywords: [[String]] = []
    private var heardForItem: [String] = []
    private var utterance: [String] = []
    private var staleInUtterance = 0
    private var judgedWords: [String] = []
    private var lastJudged = Date.distantPast
    private var judging = false
    private var judgeTimer: Timer?
    private var itemVectors: [[Float]] = []
    private var topicTracker = TopicTracker()
    private var lastItemTimer: Timer?
    private var finalTopicHeard = false

    /// The bundled sentence model, which follows paraphrased checklist items on any Mac.
    static let embedder: SentenceEmbedder? = {
        guard let model = Bundle.main.url(forResource: "SentenceEmbedding", withExtension: "mlmodelc"),
              let vocabulary = Bundle.main.url(forResource: "vocab", withExtension: "txt")
        else { return nil }
        return try? SentenceEmbedder(model: model, vocabulary: vocabulary)
    }()

    /// The sentence model only knows English, so other languages keep the older matching.
    var followsParaphrasing: Bool {
        Self.embedder != nil && itemVectors.count == items.count && speech.localeIdentifier.hasPrefix("en")
    }

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sidekick", category: "checklist")

    var isFinished: Bool {
        switch mode {
        case .script: return !tokens.isEmpty && cursor >= tokens.count
        case .checklist: return !items.isEmpty && itemCursor >= items.count
        }
    }

    var progress: Double {
        switch mode {
        case .script: return tokens.isEmpty ? 0 : Double(cursor) / Double(tokens.count)
        case .checklist: return items.isEmpty ? 0 : Double(itemCursor) / Double(items.count)
        }
    }

    var progressLabel: String {
        switch mode {
        case .script: return "\(Int((progress * 100).rounded()))%"
        case .checklist: return "\(min(itemCursor, items.count))/\(items.count)"
        }
    }

    private init() {
        speech.onWords = { [weak self] words in self?.heard(words) }
        speech.onSegmentStart = { [weak self] in self?.beginSegment() }
        speech.onFailure = { [weak self] message in self?.message = message }
        speech.$state
            .map { $0 == .listening }
            .removeDuplicates()
            .sink { [weak self] in self?.isListening = $0 }
            .store(in: &cancellables)
    }

    // MARK: Script

    func load(_ script: String) {
        guard script != loadedScript else { return }
        loadedScript = script
        tokens = ScriptParser.tokenize(script)
        follower = ScriptFollower(tokens: tokens)
        jump(to: min(cursor, tokens.count))
        if mode == .script { speech.contextualStrings = Self.distinctivePhrases(in: tokens) }
    }

    func loadChecklist(_ text: String) {
        let parsed = ChecklistParser.items(from: text)
        guard parsed != items else { return }
        var done = Dictionary(items.prefix(itemCursor).map { ($0, 1) }, uniquingKeysWith: +)
        let kept = parsed.prefix { item in
            guard let left = done[item], left > 0 else { return false }
            done[item] = left - 1
            return true
        }.count
        items = parsed
        itemKeywords = parsed.map(TopicMatcher.keywords(for:))
        itemVectors = Self.embedder.map { embedder in parsed.map { (try? embedder.embed($0)) ?? [] } } ?? []
        itemCursor = kept
        checkingItem = nil
        resetHeard()
        if mode == .checklist { speech.contextualStrings = checklistPhrases }
    }

    // MARK: Controls

    func primaryAction() {
        if !isPresenting {
            present()
        } else if isListening {
            pause()
        } else if isFinished {
            restart()
            resume()
        } else {
            resume()
        }
    }

    func present(_ newMode: PromptMode? = nil) {
        if let newMode {
            if isPresenting, newMode != mode { stop() }
            Prefs.defaults.set(newMode.rawValue, forKey: Prefs.mode)
        }
        mode = PromptMode(rawValue: Prefs.defaults.string(forKey: Prefs.mode) ?? "") ?? .script
        switch mode {
        case .script:
            load(Prefs.defaults.string(forKey: Prefs.script) ?? "")
            guard !tokens.isEmpty else {
                message = "Add a script first."
                return
            }
        case .checklist:
            loadChecklist(Prefs.defaults.string(forKey: Prefs.checklist) ?? "")
            guard !items.isEmpty else {
                message = "Add checklist items first."
                return
            }
            ChecklistJudge.prewarm()
        }
        speech.contextualStrings = mode == .script ? Self.distinctivePhrases(in: tokens) : checklistPhrases
        if isFinished { restart() }
        message = nil
        isPresenting = true
        resume()
    }

    func resume() {
        guard isPresenting, !isListening else { return }
        Task {
            if let problem = await SpeechFollower.requestPermissions() {
                message = problem
                return
            }
            speech.localeIdentifier = Prefs.defaults.string(forKey: Prefs.localeID) ?? Prefs.defaultLocaleID
            do {
                try speech.start()
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }

    func pause() {
        speech.stop()
    }

    func toggleListening() {
        isListening ? pause() : resume()
    }

    func stop() {
        speech.stop()
        isPresenting = false
    }

    func restart() {
        switch mode {
        case .script: jump(to: 0)
        case .checklist: moveItem(to: 0)
        }
    }

    func step(_ delta: Int) {
        switch mode {
        case .script: jump(to: cursor + delta)
        case .checklist: moveItem(to: itemCursor + delta)
        }
    }

    func nextSentence() {
        switch mode {
        case .script: jump(to: follower.nextSentence(after: cursor))
        case .checklist: checkOff()
        }
    }

    func previousSentence() {
        switch mode {
        case .script: jump(to: follower.previousSentence(before: cursor))
        case .checklist: moveItem(to: itemCursor - 1)
        }
    }

    // MARK: Speech

    private func jump(to index: Int) {
        cursor = min(max(index, 0), tokens.count)
        segmentStart = cursor
        wordsSeenInSegment = lastWordCount
    }

    private func beginSegment() {
        heardForItem += utterance.dropFirst(min(staleInUtterance, utterance.count))
        utterance = []
        staleInUtterance = 0
        segmentStart = cursor
        wordsSeenInSegment = 0
        lastWordCount = 0
    }

    private func heard(_ words: [String]) {
        guard mode == .script else { return heardChecklist(words) }
        lastWordCount = words.count
        let fresh = Array(words.dropFirst(min(wordsSeenInSegment, words.count)))
        let next = follower.advance(from: segmentStart, spoken: fresh)
        guard next > cursor else { return }
        cursor = next
        if isFinished { pauseWhenDone() }
    }

    private var checklistPhrases: [String] {
        // Whole items and their key words as written, so names like "Monad" or "docs" are expected.
        let words = items.flatMap { $0.split(separator: " ").map { $0.trimmingCharacters(in: .punctuationCharacters) } }
            .filter { $0.count >= 3 && !TopicMatcher.keywords(for: $0).isEmpty }
        var seen = Set<String>()
        return Array((items + words).filter { seen.insert($0.lowercased()).inserted }.prefix(100))
    }

    private func pauseWhenDone() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isFinished else { return }
                self.pause()
            }
        }
    }

    // MARK: Checklist

    /// What you've said since the current item came up.
    private var wordsForItem: [String] {
        heardForItem + utterance.dropFirst(min(staleInUtterance, utterance.count))
    }

    /// The last minute or so of `wordsForItem`.
    private var recentWords: [String] { Array(wordsForItem.suffix(120)) }

    private func heardChecklist(_ words: [String]) {
        utterance = words
        guard checkingItem == nil, itemCursor < items.count else { return }
        // Saying "moving on" or "I'm done" ticks the current item off, whatever the model thinks.
        let newest = utterance.dropFirst(min(staleInUtterance, utterance.count)).suffix(8)
        if TopicMatcher.wrapsUp(Array(newest)) { return checkOff() }
        let recent = recentWords
        if followsParaphrasing, let embedder = Self.embedder {
            return followTopic(with: embedder, recent: recent)
        }
        let spoken = TopicMatcher.lemmas(in: recent.joined(separator: " "))
        // With Apple Intelligence, key words only show you've started an item, so the model decides when it's done.
        if !ChecklistJudge.isReady, TopicMatcher.covers(keywords: itemKeywords[itemCursor], spoken: spoken, strict: false) {
            return checkOff()
        }
        // Saying the next item's key words suggests you've moved on from this one. With Apple Intelligence,
        // ask the model right away, since you might only be previewing it.
        if itemCursor + 1 < items.count {
            let latest = TopicMatcher.lemmas(in: recent.suffix(30).joined(separator: " "))
            if TopicMatcher.covers(keywords: itemKeywords[itemCursor + 1], spoken: latest, strict: ChecklistJudge.isReady) {
                guard ChecklistJudge.isReady else { return checkOff(carrying: Array(recent.suffix(30))) }
                judgeTimer?.invalidate()
                if wordsForItem != judgedWords { judge() }
                return
            }
        }
        scheduleJudge()
    }

    /// Moves on once your latest words clearly match a later item better than the current one.
    private func followTopic(with embedder: SentenceEmbedder, recent: [String]) {
        let upcoming = Array(itemCursor..<min(itemCursor + 3, items.count))
        if upcoming.count > 1, let spoken = try? embedder.embed(recent.suffix(12).joined(separator: " ")) {
            let scores = upcoming.map { SentenceEmbedder.similarity(spoken, itemVectors[$0]) }
            let moved = topicTracker.update(scores: scores, heard: wordsForItem.count)
            Self.log.debug("""
            \(moved > 0 ? "moved on" : "on", privacy: .public) · \(self.items[self.itemCursor], privacy: .public) · \
            scores \(scores.map { String(format: "%.2f", $0) }.joined(separator: " "), privacy: .public) · \
            heard “\(recent.suffix(12).joined(separator: " "), privacy: .public)”
            """)
            if moved > 0 {
                let landsOnLast = itemCursor + moved == items.count - 1
                checkOff(through: itemCursor + moved - 1, carrying: Array(recent.suffix(12)))
                finalTopicHeard = landsOnLast
                return
            }
        }
        guard itemCursor == items.count - 1 else { return }
        // With nothing before it, or a previous item that means the same, there's nothing to tell apart.
        if itemCursor == 0 || SentenceEmbedder.similarity(itemVectors[itemCursor], itemVectors[itemCursor - 1]) > 0.95 {
            finalTopicHeard = true
        } else if let spoken = try? embedder.embed(recent.suffix(12).joined(separator: " ")) {
            let last = SentenceEmbedder.similarity(spoken, itemVectors[itemCursor])
            let previous = SentenceEmbedder.similarity(spoken, itemVectors[itemCursor - 1])
            if last - previous > topicTracker.margin { finalTopicHeard = true }
        }
        armLastItem()
    }

    /// The last item has nothing after it, so it ticks off once you've talked about it and gone quiet.
    private func armLastItem() {
        lastItemTimer?.invalidate()
        guard followsParaphrasing, itemCursor == items.count - 1, finalTopicHeard, wordsForItem.count >= 6 else { return }
        let index = itemCursor
        lastItemTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.itemCursor == index, self.isListening else { return }
                self.checkOff()
            }
        }
    }

    /// Asks the model after a short pause in speech, or every couple of seconds while you keep talking.
    /// A couple of new words, like "moving on", wait for the pause.
    private func scheduleJudge() {
        guard ChecklistJudge.isReady, wordsForItem != judgedWords else { return }
        judgeTimer?.invalidate()
        let fewNewWords = wordsForItem.count < judgedWords.count + 3
        let delay = !fewNewWords && Date().timeIntervalSince(lastJudged) > 2.5 ? 0 : 0.7
        judgeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.judge() }
        }
    }

    private func judge() {
        guard !judging, checkingItem == nil, itemCursor < items.count else { return }
        let index = itemCursor
        let words = recentWords
        guard !words.isEmpty else { return }
        judging = true
        judgedWords = wordsForItem
        lastJudged = Date()
        let previous = index > 0 ? items[index - 1] : nil
        let upcoming = Array(items[index..<min(index + 3, items.count)])
        Task {
            let done = await ChecklistJudge.itemsDone(
                upcoming: upcoming, previous: previous, transcript: words.joined(separator: " ")
            )
            judging = false
            if let done, done > 0, index == itemCursor, checkingItem == nil {
                checkOff(through: index + done - 1)
            } else if wordsForItem != judgedWords {
                scheduleJudge()
            }
        }
    }

    /// Ticks off the current item, and every item up to `last` if you've already covered those too.
    /// `carrying` words still count toward the item after, such as the ones that introduced it.
    private func checkOff(through last: Int? = nil, carrying: [String] = []) {
        guard checkingItem == nil, itemCursor < items.count else { return }
        let index = itemCursor
        checkingItem = index
        resetHeard()
        heardForItem = carrying
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.checkingItem == index else { return }
                self.checkingItem = nil
                self.itemCursor = min(max(last ?? index, index), self.items.count - 1) + 1
                if self.isFinished { self.pauseWhenDone() } else { self.armLastItem() }
            }
        }
    }

    private func moveItem(to index: Int) {
        checkingItem = nil
        itemCursor = min(max(index, 0), items.count)
        resetHeard()
    }

    /// Words already heard no longer count toward the next item.
    private func resetHeard() {
        heardForItem = []
        staleInUtterance = utterance.count
        judgedWords = []
        topicTracker.reset()
        lastItemTimer?.invalidate()
        finalTopicHeard = false
        judgeTimer?.invalidate()
    }

    private static func distinctivePhrases(in tokens: [ScriptToken]) -> [String] {
        var seen = Set<String>()
        var phrases: [String] = []
        for token in tokens where token.key.count >= 6 && seen.insert(token.key).inserted {
            let word = token.text.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
            phrases.append(word)
            if phrases.count == 100 { break }
        }
        return phrases
    }
}
