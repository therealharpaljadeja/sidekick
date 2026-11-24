import Foundation
import XCTest
@testable import SidekickCore

final class ChecklistTests: XCTestCase {
    func testParsesBulletsNumbersAndBoxes() {
        let text = """
        - Intro and who I am
        2. Paste a script
        * [ ] Hide from recordings

        • Pricing
        Wrap up
        """
        XCTAssertEqual(ChecklistParser.items(from: text),
                       ["Intro and who I am", "Paste a script", "Hide from recordings", "Pricing", "Wrap up"])
    }

    func testKeywordsDropPresentingWords() {
        XCTAssertEqual(TopicMatcher.keywords(for: "Show how to hide Sidekick from screen recordings"),
                       ["hide", "sidekick", "screen", "recording"])
    }

    func testCoverageAcrossInflections() {
        let keywords = TopicMatcher.keywords(for: "Show how to hide Sidekick from screen recordings")
        let spoken = TopicMatcher.lemmas(in: "now I am hiding sidekick so the screen recording can't see it")
        XCTAssertTrue(TopicMatcher.covers(keywords: keywords, spoken: spoken))
        let unrelated = TopicMatcher.lemmas(in: "let me paste my script into the editor")
        XCTAssertFalse(TopicMatcher.covers(keywords: keywords, spoken: unrelated))
    }

    func testShortItemsNeedEveryKeyword() {
        let keywords = TopicMatcher.keywords(for: "Pricing")
        XCTAssertTrue(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "so what about pricing")))
        XCTAssertFalse(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "it is free")))
    }

    func testStrictNeedsAllKeywords() {
        let keywords = TopicMatcher.keywords(for: "Hide from screen recordings")
        XCTAssertFalse(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "hide it from the screen"), strict: true))
        XCTAssertTrue(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "hide it from screen recordings"), strict: true))
    }

    func testStrictShortItemMatchesExactWord() {
        let keywords = TopicMatcher.keywords(for: "Pricing")
        XCTAssertTrue(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "pricing"), strict: true))
    }

    func testOneSpokenWordCountsOnce() {
        let keywords = TopicMatcher.keywords(for: "Privacy and private browsing")
        XCTAssertFalse(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "privacy")))
        XCTAssertTrue(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "privacy and private browsing")))
    }

    func testStrictIgnoresSharedPrefix() {
        let keywords = TopicMatcher.keywords(for: "Discovery")
        XCTAssertFalse(TopicMatcher.covers(keywords: keywords, spoken: TopicMatcher.lemmas(in: "discount"), strict: true))
    }

    func testWrapUpPhrases() {
        XCTAssertTrue(TopicMatcher.wrapsUp("so I am done Moving on".split(separator: " ").map(String.init)))
        XCTAssertTrue(TopicMatcher.wrapsUp("that’s it for the docs".split(separator: " ").map(String.init)))
        XCTAssertTrue(TopicMatcher.wrapsUp(["I'm", "done"]))
        XCTAssertTrue(TopicMatcher.wrapsUp(["okay", "moving on"]))
        XCTAssertFalse(TopicMatcher.wrapsUp("to select the next item press down".split(separator: " ").map(String.init)))
        XCTAssertFalse(TopicMatcher.wrapsUp("the moving parts are done online".split(separator: " ").map(String.init)))
    }

    func testTrackerNeedsASustainedLead() {
        var tracker = TopicTracker(margin: 0.05, wordsToHold: 3)
        XCTAssertEqual(tracker.update(scores: [0.7, 0.8, 0.5], heard: 1), 0)
        XCTAssertEqual(tracker.update(scores: [0.7, 0.6, 0.5], heard: 2), 0)
        XCTAssertEqual(tracker.update(scores: [0.6, 0.8, 0.5], heard: 3), 0)
        XCTAssertEqual(tracker.update(scores: [0.6, 0.8, 0.5], heard: 3), 0)
        XCTAssertEqual(tracker.update(scores: [0.6, 0.8, 0.5], heard: 4), 0)
        XCTAssertEqual(tracker.update(scores: [0.6, 0.8, 0.5], heard: 5), 1)
    }

    func testTrackerSkipsToTheItemYoureOn() {
        var tracker = TopicTracker(margin: 0.05, wordsToHold: 2)
        XCTAssertEqual(tracker.update(scores: [0.5, 0.6, 0.8], heard: 10), 0)
        XCTAssertEqual(tracker.update(scores: [0.5, 0.6, 0.8], heard: 11), 2)
    }

    func testTokenizerMatchesBert() throws {
        let vocab = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Resources/Model/vocab.txt").standardizedFileURL
        let tokenizer = try WordPieceTokenizer(vocabulary: vocab)
        XCTAssertEqual(Array(tokenizer.encode("So when you know I'm using command-H, it's café").ids.prefix(18)),
                       [101, 2061, 2043, 2017, 2113, 1045, 1005, 1049, 2478, 3094, 1011, 1044, 1010, 2009, 1005, 1055, 7668, 102])
    }
}
