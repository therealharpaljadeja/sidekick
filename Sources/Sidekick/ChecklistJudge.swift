import Foundation
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
    static func covers(item: String, next: String?, transcript: String) async -> Bool? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), isReady {
            return await AIJudge.shared.covers(item: item, next: next, transcript: transcript)
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
private struct TopicCheck {
    @Guide(description: "True if the presenter has started talking about or doing the current item.")
    var covered: Bool
}

@available(macOS 26.0, *)
@MainActor
private final class AIJudge {
    static let shared = AIJudge()

    private static let instructions = """
    You follow a presenter recording a video demo from an ordered checklist of talking points. \
    You get the current checklist item and a live speech-recognition transcript of what they just said, \
    which may contain recognition mistakes. Decide whether the presenter has started talking about \
    or doing the current item. They paraphrase and rarely use the item's exact words, so judge the meaning. \
    Answer true as soon as they are clearly on the current item or past it. Answer false if they are still \
    on an earlier topic, making small talk, or only saying they will get to it later.
    """

    func prewarm() {
        LanguageModelSession(instructions: Self.instructions).prewarm()
    }

    func covers(item: String, next: String?, transcript: String) async -> Bool? {
        // A fresh session per check keeps each verdict independent and the context small.
        let session = LanguageModelSession(instructions: Self.instructions)
        var prompt = "Current item: \"\(item)\"\n"
        if let next { prompt += "Item after it: \"\(next)\"\n" }
        prompt += "Transcript: \"\(transcript)\""
        do {
            let response = try await session.respond(
                to: prompt, generating: TopicCheck.self, options: GenerationOptions(temperature: 0)
            )
            return response.content.covered
        } catch {
            return nil
        }
    }
}
#endif
