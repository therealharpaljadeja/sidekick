import XCTest
@testable import SidekickCore

final class ScriptFollowerTests: XCTestCase {
    private let script = """
    Hey everyone — today I'm going to show you Sidekick, a teleprompter that lives in your notch. \
    It listens while you talk and moves along with you. Let's record a quick on-device demo.
    """

    private var follower: ScriptFollower { ScriptFollower(tokens: ScriptParser.tokenize(script)) }

    func testTokenizeKeepsPunctuationWithWords() {
        let tokens = ScriptParser.tokenize(script)
        XCTAssertEqual(tokens[0].key, "hey")
        XCTAssertEqual(tokens[1].text, "everyone —")
        XCTAssertEqual(tokens[2].key, "today")
        XCTAssertEqual(tokens[3].key, "im")
        XCTAssertTrue(tokens.first { $0.key == "notch" }!.endsSentence)
        let on = tokens.firstIndex { $0.key == "on" && !$0.trailingSpace }!
        XCTAssertEqual(tokens[on].text, "on-")
        XCTAssertEqual(tokens[on + 1].key, "device")
    }

    func testFollowsExactSpeech() {
        let spoken = "hey everyone today I'm going to show you".split(separator: " ").map(String.init)
        XCTAssertEqual(follower.advance(from: 0, spoken: spoken), 8)
    }

    func testIgnoresFillerWords() {
        let spoken = "hey um everyone uh today".split(separator: " ").map(String.init)
        XCTAssertEqual(follower.advance(from: 0, spoken: spoken), 3)
    }

    func testCatchesUpAfterMissedWords() {
        // Recognizer dropped "going to show".
        let spoken = ["hey", "everyone", "today", "I'm", "you", "Sidekick"]
        XCTAssertEqual(follower.advance(from: 0, spoken: spoken), 9)
    }

    func testCommonWordDoesNotJumpAhead() {
        // Ad-libbed "the" must not jump to a later "the"/"a".
        let f = ScriptFollower(tokens: ScriptParser.tokenize("record the app and then share the link"))
        XCTAssertEqual(f.advance(from: 2, spoken: ["so", "and", "the"]), 2)
    }

    func testFuzzyMatchesMisrecognitions() {
        let spoken = ["hey", "everyone", "today", "im", "going", "to", "show", "you", "side", "kick", "a", "teleprompters"]
        XCTAssertGreaterThanOrEqual(follower.advance(from: 0, spoken: spoken), 11)
    }

    func testResyncsAfterSkippingSentence() {
        let tokens = ScriptParser.tokenize(script)
        let target = tokens.firstIndex { $0.key == "record" }!
        let spoken = ["lets", "record", "a", "quick"]
        XCTAssertEqual(follower.advance(from: 0, spoken: spoken), target + 3)
    }

    func testSentenceNavigation() {
        let f = follower
        let next = f.nextSentence(after: 0)
        XCTAssertEqual(f.tokens[next].key, "it")
        XCTAssertEqual(f.previousSentence(before: next + 2), next)
        XCTAssertEqual(f.previousSentence(before: next), 0)
    }

    func testUtteranceRestartAfterPauseIsNew() {
        XCTAssertTrue(Utterance.isNew(["next"], after: ["it", "listens", "while", "you", "talk"]))
        XCTAssertTrue(Utterance.isNew(["it"], after: ["it", "listens", "while", "you", "talk"]))
    }

    func testUtteranceRevisionIsNotNew() {
        XCTAssertFalse(Utterance.isNew(["go", "now"], after: ["uh", "go", "now"]))
        XCTAssertFalse(Utterance.isNew(["go", "now"], after: ["um", "uh", "go", "now"]))
        XCTAssertFalse(Utterance.isNew(["go", "now", "please"], after: ["go", "now", "please", "ok"]))
        XCTAssertFalse(Utterance.isNew(["go", "now", "please", "ok"], after: ["go", "now"]))
    }
}
