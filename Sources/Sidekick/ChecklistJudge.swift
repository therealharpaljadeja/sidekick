import Foundation
import os
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Decides whether what you said covers a checklist item, using Apple Intelligence's on-device
/// model when this Mac has it (macOS 26+), so paraphrases count.
@MainActor
enum ChecklistJudge {
    enum Status: Equatable {
        case ready
        case unavailable(String)
    }

    static var status: Status {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Turn on Apple Intelligence in System Settings to understand paraphrasing.")
            case .unavailable(.modelNotReady):
                return .unavailable("Apple Intelligence is still downloading. Matching key words for now.")
            case .unavailable:
                return .unavailable("This Mac can't run Apple Intelligence, so Sidekick matches key words.")
            }
        }
        #endif
        return .unavailable("Understanding paraphrasing needs macOS 26 with Apple Intelligence. Matching key words for now.")
    }

    static var isReady: Bool { status == .ready }

    static func prewarm() {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isReady { AIJudge.shared.prewarm() }
        #endif
    }

    /// How many of `upcoming` you're done with, starting from the current item: 0 while you're still on it.
    /// `nil` when the model can't answer, so the caller can rely on key words instead.
    static func itemsDone(upcoming: [String], previous: String?, transcript: String) async -> Int? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isReady {
            return await AIJudge.shared.itemsDone(upcoming: upcoming, previous: previous, transcript: transcript)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct TopicCheck {
    @Guide(description: "A few words on what the presenter is talking about or doing at the end of the transcript.")
    var nowTalkingAbout: String
    @Guide(description: "The number of the checklist item they're talking about or doing at the end of the transcript, or 0 if it's none of them.", .range(0...3))
    var onItem: Int
    @Guide(description: "True if, at the end of the transcript, they wrap up item 1, like \"so that's…\", \"that's it for…\" or \"moving on\".")
    var wrappedUpItemOne: Bool
}

@available(macOS 26.0, *)
@MainActor
private final class AIJudge {
    static let shared = AIJudge()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sidekick", category: "checklist")

    private static let latestWords = 30

    private static let instructions = """
    You follow a presenter recording a video demo from an ordered checklist of talking points. \
    You get the next few checklist items, numbered from 1, and the last few sentences of a live \
    speech-recognition transcript. The transcript has no punctuation and may contain recognition mistakes, \
    such as a name heard as a similar-sounding word. The presenter paraphrases, so judge the meaning, \
    not the exact words. Say which numbered item they're talking about or doing at the end of the transcript. \
    Pick an item only if they're on it now, not if they only say they'll get to it later. \
    Answer 0 for small talk or a topic that isn't on the list. Also say whether they just wrapped up item 1.
    """

    func prewarm() {
        LanguageModelSession(instructions: Self.instructions).prewarm()
    }

    func itemsDone(upcoming: [String], previous: String?, transcript: String) async -> Int? {
        // A fresh session per check keeps each verdict independent and the context small.
        let session = LanguageModelSession(instructions: Self.instructions)
        var prompt = ""
        if let previous { prompt += "Already done: \"\(previous)\"\n" }
        prompt += "Checklist:\n"
        for (number, item) in upcoming.enumerated() { prompt += "\(number + 1). \(item)\n" }
        let words = transcript.split(separator: " ").suffix(Self.latestWords)
        prompt += "Transcript: \"\(words.joined(separator: " "))\""
        do {
            let response = try await session.respond(
                to: prompt, generating: TopicCheck.self, options: GenerationOptions(temperature: 0)
            )
            let check = response.content
            let onItem = min(max(check.onItem, 0), upcoming.count)
            let done = max(onItem - 1, check.wrappedUpItemOne ? 1 : 0)
            Self.log.debug("""
            ticks \(done, privacy: .public) · on item \(onItem, privacy: .public) · wrapped up item 1: \(check.wrappedUpItemOne, privacy: .public) · \
            model: \(check.nowTalkingAbout, privacy: .public) · sent: \(prompt.replacingOccurrences(of: "\n", with: " | "), privacy: .public)
            """)
            return done
        } catch {
            Self.log.error("Apple Intelligence failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
