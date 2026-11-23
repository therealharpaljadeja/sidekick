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

    /// True once you've finished the item or moved on to the next one. `nil` when the model can't answer, so the caller can rely on key words instead.
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
private enum Stage {
    case stillOnPrevious
    case onCurrent
    case finishedCurrent
    case onNext
}

@available(macOS 26.0, *)
@Generable
private struct TopicCheck {
    @Guide(description: "A few words on what the presenter is talking about or doing at the very end of the transcript.")
    var nowTalkingAbout: String
    @Guide(description: "Where the presenter is at the very end of the transcript.")
    var stage: Stage
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
    Pick the stage that describes where the presenter is at the very end of the transcript: \
    stillOnPrevious if they're still on the previous item or haven't started the current one; \
    onCurrent if they're introducing, talking about or doing the current item and haven't wrapped it up; \
    finishedCurrent only if they clearly say they're done with it ("so that's…", "that's it for…", "moving on"); \
    onNext only if they've actually started talking about or doing the item after it. \
    Being on the current item, mentioning its words, or saying what's coming later does not finish it. \
    When unsure, answer onCurrent.
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
            Self.log.debug("\(String(describing: check.stage), privacy: .public) · \(item, privacy: .public) · heard “\(transcript, privacy: .public)” · model: \(check.nowTalkingAbout, privacy: .public)")
            return check.stage == .finishedCurrent || check.stage == .onNext
        } catch {
            Self.log.error("Apple Intelligence failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
#endif
