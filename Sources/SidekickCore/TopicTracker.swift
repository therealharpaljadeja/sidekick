/// Decides when you've moved on to a later checklist item, from how closely your latest words match
/// each upcoming item. A later item has to beat the current one clearly for several new words in a row,
/// so a passing mention doesn't skip ahead.
public struct TopicTracker: Sendable {
    public var margin: Float
    public var wordsToHold: Int
    private var candidate = 0
    private var since = 0

    public init(margin: Float = 0.06, wordsToHold: Int = 6) {
        self.margin = margin
        self.wordsToHold = wordsToHold
    }

    public mutating func reset() { candidate = 0 }

    /// `scores[0]` is the current item and the rest are the items after it; `heard` counts the words
    /// heard so far for the current item. Returns how many items you've moved past (0 to stay).
    public mutating func update(scores: [Float], heard: Int) -> Int {
        guard scores.count > 1,
              let best = scores.indices.dropFirst().max(by: { scores[$0] < scores[$1] }),
              scores[best] - scores[0] > margin
        else { candidate = 0; return 0 }
        if candidate != best { candidate = best; since = heard }
        guard heard - since + 1 >= wordsToHold else { return 0 }
        candidate = 0
        return best
    }
}
