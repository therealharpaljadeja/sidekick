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
    @Published var message: String?

    let speech = SpeechFollower()

    private var follower = ScriptFollower(tokens: [])
    private var loadedScript = ""
    private var segmentStart = 0
    private var wordsSeenInSegment = 0
    private var lastWordCount = 0
    private var cancellables = Set<AnyCancellable>()

    var isFinished: Bool { !tokens.isEmpty && cursor >= tokens.count }
    var progress: Double { tokens.isEmpty ? 0 : Double(cursor) / Double(tokens.count) }

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
        speech.contextualStrings = Self.distinctivePhrases(in: tokens)
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

    func present() {
        load(Prefs.defaults.string(forKey: Prefs.script) ?? "")
        guard !tokens.isEmpty else {
            message = "Add a script first."
            return
        }
        if isFinished { jump(to: 0) }
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
        jump(to: 0)
    }

    func step(_ delta: Int) {
        jump(to: cursor + delta)
    }

    func nextSentence() {
        jump(to: follower.nextSentence(after: cursor))
    }

    func previousSentence() {
        jump(to: follower.previousSentence(before: cursor))
    }

    // MARK: Speech

    private func jump(to index: Int) {
        cursor = min(max(index, 0), tokens.count)
        segmentStart = cursor
        wordsSeenInSegment = lastWordCount
    }

    private func beginSegment() {
        segmentStart = cursor
        wordsSeenInSegment = 0
        lastWordCount = 0
    }

    private func heard(_ words: [String]) {
        lastWordCount = words.count
        let fresh = Array(words.dropFirst(min(wordsSeenInSegment, words.count)))
        let next = follower.advance(from: segmentStart, spoken: fresh)
        guard next > cursor else { return }
        cursor = next
        if isFinished {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isFinished else { return }
                    self.pause()
                }
            }
        }
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
