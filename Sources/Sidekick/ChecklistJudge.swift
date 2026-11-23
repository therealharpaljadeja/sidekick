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

    /// `nil` when the model can't answer, so the caller can rely on key words instead.
    static func covers(item: String, previous: String?, next: String?, transcript: String) async -> Bool? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isReady {
            return await AIJudge.shared.covers(item: item, previous: previous, next: next, transcript: transcript)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct TopicCheck {
    @Guide(description: "A few words on what the presenter is talking about or doing right now.")
    var nowTalkingAbout: String
    @Guide(description: "True if the presenter is on the current item, has said they're done with it, or has moved on to the item after it.")
    var covered: Bool
}

@available(macOS 26.0, *)
@MainActor
private final class AIJudge {
    static let shared = AIJudge()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sidekick", category: "checklist")

    private static let instructions = """
    You follow a presenter recording a video demo from an ordered checklist of talking points. \
    You get the current checklist item, its neighbours, and a live speech-recognition transcript of what \
    the presenter said since the current item came up. The transcript has no punctuation and may contain \
    recognition mistakes. The presenter paraphrases and rarely uses the item's words, so judge the meaning. \
    Answer covered = true if any of these hold: \
    they are talking about or doing the current item, even briefly or in their own words; \
    they introduce it ("now let me show you…", "next up…"); \
    they say they're done with it ("so that's…", "that's it for…", "moving on"); \
    or they have moved on to the item after it. \
    Answer false only if they are still on the previous item or saying something unrelated to the current item.
    """

    func prewarm() {
        LanguageModelSession(instructions: Self.instructions).prewarm()
    }

    func covers(item: String, previous: String?, next: String?, transcript: String) async -> Bool? {
        // A fresh session per check keeps each verdict independent and the context small.
        let session = LanguageModelSession(instructions: Self.instructions)
        var prompt = ""
        if let previous { prompt += "Previous item (already done): \"\(previous)\"\n" }
        prompt += "Current item: \"\(item)\"\n"
        if let next { prompt += "Item after it: \"\(next)\"\n" }
        prompt += "Transcript: \"\(transcript)\""
        do {
            let response = try await session.respond(
                to: prompt, generating: TopicCheck.self, options: GenerationOptions(temperature: 0)
            )
            let check = response.content
            Self.log.debug("\(check.covered ? "covered" : "not yet", privacy: .public) · \(item, privacy: .public) · heard “\(transcript, privacy: .public)” · model: \(check.nowTalkingAbout, privacy: .public)")
            return check.covered
        } catch {
            Self.log.error("Apple Intelligence failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
