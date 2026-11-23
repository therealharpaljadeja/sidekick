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
    private var judgedWordCount = 0
    private var lastJudged = Date.distantPast
    private var judging = false
    private var judgeTimer: Timer?

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
        var seen = Set<String>()
        return Array(itemKeywords.joined().filter { $0.count >= 4 && seen.insert($0).inserted }.prefix(100))
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
        let recent = recentWords
        let spoken = TopicMatcher.lemmas(in: recent.joined(separator: " "))
        if TopicMatcher.covers(keywords: itemKeywords[itemCursor], spoken: spoken, strict: ChecklistJudge.isReady) {
            return checkOff()
        }
        scheduleJudge()
    }

    /// Asks the model after a short pause in speech, or every couple of seconds while you keep talking.
    private func scheduleJudge() {
        guard ChecklistJudge.isReady, wordsForItem.count >= judgedWordCount + 3 else { return }
        judgeTimer?.invalidate()
        let delay = Date().timeIntervalSince(lastJudged) > 2.5 ? 0 : 0.7
        judgeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.judge() }
        }
    }

    private func judge() {
        guard !judging, checkingItem == nil, itemCursor < items.count else { return }
        let index = itemCursor
        let words = recentWords
        guard words.count >= 3 else { return }
        judging = true
        judgedWordCount = wordsForItem.count
        lastJudged = Date()
        let next = index + 1 < items.count ? items[index + 1] : nil
        Task {
            let covered = await ChecklistJudge.covers(item: items[index], next: next, transcript: words.joined(separator: " "))
            judging = false
            if covered == true, index == itemCursor, checkingItem == nil {
                checkOff()
            } else if wordsForItem.count >= judgedWordCount + 3 {
                scheduleJudge()
            }
        }
    }

    private func checkOff() {
        guard checkingItem == nil, itemCursor < items.count else { return }
        let index = itemCursor
        checkingItem = index
        resetHeard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.checkingItem == index else { return }
                self.checkingItem = nil
                self.itemCursor = index + 1
                if self.isFinished { self.pauseWhenDone() }
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
        judgedWordCount = 0
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
