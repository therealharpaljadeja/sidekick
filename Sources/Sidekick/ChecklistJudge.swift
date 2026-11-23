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

    private static let latestWords = 25

    private static let instructions = """
    You follow a presenter recording a video demo from an ordered checklist of talking points. \
    You get the previous, current and next checklist items, and a live speech-recognition transcript of \
    what the presenter said since the current item came up, split into "Earlier" and "Just now". \
    The transcript has no punctuation and may contain recognition mistakes. The presenter paraphrases \
    and rarely uses the items' words, so judge the meaning. \
    Decide where the presenter is in "Just now": \
    onNext if "Just now" is about the next item, or about any topic that isn't the current item \
    after they've already talked about the current item "Earlier"; \
    finishedCurrent if they wrap up the current item ("so that's…", "that's it for…", "moving on", "okay, next"); \
    onCurrent if they're still introducing, explaining or doing the current item; \
    stillOnPrevious if they haven't started the current item yet.
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
        let words = transcript.split(separator: " ")
        let earlier = words.dropLast(Self.latestWords).joined(separator: " ")
        if !earlier.isEmpty { prompt += "Earlier: \"\(earlier)\"\n" }
        prompt += "Just now: \"\(words.suffix(Self.latestWords).joined(separator: " "))\""
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
