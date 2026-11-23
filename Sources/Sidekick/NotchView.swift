import AppKit
import SidekickCore
import SwiftUI

struct NotchView: View {
    @EnvironmentObject private var prompter: Prompter
    @EnvironmentObject private var geometry: NotchGeometry
    @AppStorage(Prefs.fontSize) private var fontSize = 18.0
    @AppStorage(Prefs.lineCount) private var lineCount = 2
    @AppStorage(Prefs.panelWidth) private var panelWidth = 620.0

    private var expanded: Bool { prompter.isPresenting }

    private var size: CGSize {
        expanded
            ? geometry.expandedSize(width: panelWidth, fontSize: fontSize, lines: lineCount)
            : geometry.notchSize
    }

    var body: some View {
        ZStack(alignment: .top) {
            NotchShape(topRadius: expanded ? 10 : 6, bottomRadius: expanded ? 20 : 10)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
                .opacity(expanded || geometry.hasNotch ? 1 : 0)

            if expanded {
                content
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: expanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: size)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StatusLabel()
                Spacer(minLength: geometry.hasNotch ? geometry.notchSize.width + 16 : 16)
                HStack(spacing: 12) {
                    PrivacyLight()
                    Text(prompter.progressLabel)
                        .font(Theme.intern(11, .medium))
                        .monospacedDigit()
                        .foregroundColor(Theme.secondary)
                }
            }
            .padding(.horizontal, 26)
            .frame(height: geometry.notchSize.height)

            Group {
                switch prompter.mode {
                case .script:
                    PromptText(
                        tokens: prompter.tokens,
                        cursor: prompter.cursor,
                        fontSize: fontSize,
                        lines: lineCount,
                        width: size.width - 52
                    )
                case .checklist:
                    ChecklistRoll(
                        items: prompter.items,
                        cursor: prompter.itemCursor,
                        checking: prompter.checkingItem,
                        fontSize: fontSize,
                        lines: lineCount,
                        width: size.width - 52
                    )
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, NotchLayout.textTopPadding)

            Spacer(minLength: 0)
        }
        .overlay(
            EventCatcher(
                onClick: { prompter.toggleListening() },
                onScroll: { prompter.step($0) }
            )
        )
    }

}

private struct StatusLabel: View {
    @EnvironmentObject private var prompter: Prompter
    @EnvironmentObject private var speech: SpeechFollower

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(prompter.isListening ? Theme.text : Theme.tertiary)
                .frame(width: 6, height: 6)
                .scaleEffect(prompter.isListening ? 1 + CGFloat(speech.level) * 0.7 : 1)
                .animation(.easeOut(duration: 0.12), value: speech.level)
            Text(label)
                .font(Theme.intern(11, .medium))
                .foregroundColor(Theme.secondary)
                .lineLimit(1)
        }
    }

    private var label: String {
        if prompter.isFinished { return "Done" }
        if prompter.message != nil { return "Needs attention" }
        return prompter.isListening ? "Listening" : "Paused"
    }
}

/// Hollow when Sidekick is hidden from recordings; a lit dot when recordings can see it.
private struct PrivacyLight: View {
    @AppStorage(Prefs.hideFromCapture) private var hidden = true

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Theme.tertiary, lineWidth: 1)
                    .opacity(hidden ? 1 : 0)
                Circle()
                    .fill(Theme.text)
                    .shadow(color: Theme.text.opacity(0.8), radius: 3)
                    .opacity(hidden ? 0 : 1)
            }
            .frame(width: 6, height: 6)
            Text(hidden ? "Hidden" : "In recordings")
                .font(Theme.intern(11, .medium))
                .foregroundColor(hidden ? Theme.secondary : Theme.text)
                .lineLimit(1)
        }
        .animation(.easeOut(duration: 0.2), value: hidden)
        .help(hidden ? "Hidden from ScreenCaptureKit recorders (QuickTime, OBS, Zoom, screenshots). Legacy capture tools may still see it." : "Visible in screen recordings")
    }
}

/// The whole script rolling up like credits: the line you're on sits at the top, the next few
/// words are highlighted (everything else stays normal grey), and the lines below fade out so you can tell more is coming.
private struct PromptText: View {
    let tokens: [ScriptToken]
    let cursor: Int
    let fontSize: Double
    let lines: Int
    let width: CGFloat

    private static let highlightedWords = 6

    private var lineHeight: CGFloat { CGFloat(fontSize) * NotchLayout.lineHeightMultiple }
    private var tracking: CGFloat { fontSize >= 22 ? -0.2 : 0 }
    private var height: CGFloat { lineHeight * (CGFloat(max(lines, 1)) + NotchLayout.peekLines) }

    var body: some View {
        if tokens.isEmpty {
            message("Paste a script in Sidekick to begin.")
        } else if cursor >= tokens.count {
            message("That's a wrap.")
        } else {
            roll
        }
    }

    private var roll: some View {
        let layout = CreditsLayout.shared.lines(for: tokens, width: width, fontSize: fontSize, tracking: tracking)
        let current = layout.firstIndex { $0.contains(cursor) } ?? 0
        let visible = max(0, current - 1)...min(layout.count - 1, current + max(lines, 1) + 1)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(visible), id: \.self) { index in
                line(layout[index])
                    .frame(width: width, height: lineHeight, alignment: .leading)
                    .offset(y: CGFloat(index - current) * lineHeight)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.5, dampingFraction: 1), value: current)
        .drawingGroup()
        .mask(fade)
    }

    private func line(_ range: Range<Int>) -> some View {
        range.reduce(Text("")) { text, index in
            text + Text(tokens[index].displayText).foregroundColor(color(for: index))
        }
        .font(Theme.intern(fontSize, .medium))
        .tracking(tracking)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func color(for index: Int) -> Color {
        (cursor..<cursor + Self.highlightedWords).contains(index) ? .white : Color(white: 0.46)
    }

    private var fade: some View { creditsFade(lines: lines) }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.intern(fontSize, .medium))
            .foregroundColor(Theme.secondary)
            .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// Solid over the full lines, then fading through the line that peeks in below.
private func creditsFade(lines: Int) -> some View {
    let full = CGFloat(max(lines, 1))
    return LinearGradient(
        stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: (full - 0.15) / (full + NotchLayout.peekLines)),
            .init(color: .clear, location: 1),
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}

/// The next items to cover, one per line. A covered item ticks, then rolls up and away.
private struct ChecklistRoll: View {
    let items: [String]
    let cursor: Int
    let checking: Int?
    let fontSize: Double
    let lines: Int
    let width: CGFloat

    private var lineHeight: CGFloat { CGFloat(fontSize) * NotchLayout.lineHeightMultiple }
    private var height: CGFloat { lineHeight * (CGFloat(max(lines, 1)) + NotchLayout.peekLines) }

    var body: some View {
        if items.isEmpty {
            message("Add a checklist in Sidekick to begin.")
        } else if cursor >= items.count {
            message("Everything's covered. That's a wrap.")
        } else {
            roll
        }
    }

    private var roll: some View {
        let visible = max(0, cursor - 1)...min(items.count - 1, cursor + max(lines, 1))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(visible), id: \.self) { index in
                row(index)
                    .frame(width: width, height: lineHeight, alignment: .leading)
                    .offset(y: CGFloat(index - cursor) * lineHeight)
                    .opacity(index < cursor ? 0 : 1)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .animation(.spring(response: 0.5, dampingFraction: 1), value: cursor)
        .animation(.easeOut(duration: 0.2), value: checking)
        .drawingGroup()
        .mask(creditsFade(lines: lines))
    }

    private func row(_ index: Int) -> some View {
        let done = index < cursor || index == checking
        let box = CGFloat(fontSize) * 0.62
        return HStack(spacing: CGFloat(fontSize) * 0.55) {
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(index == cursor ? Theme.text : Theme.tertiary, lineWidth: 1)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.text)
                    .opacity(done ? 1 : 0)
                Image(systemName: "checkmark")
                    .font(.system(size: box * 0.62, weight: .bold))
                    .foregroundColor(.black)
                    .opacity(done ? 1 : 0)
            }
            .frame(width: box, height: box)
            Text(items[index])
                .font(Theme.intern(fontSize, .medium))
                .foregroundColor(index == cursor && !done ? .white : Color(white: 0.46))
                .strikethrough(done, color: Color(white: 0.46))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.intern(fontSize, .medium))
            .foregroundColor(Theme.secondary)
            .frame(width: width, height: height, alignment: .topLeading)
    }
}

/// Splits the script into the lines it wraps to at the notch width, as token ranges.
@MainActor
private final class CreditsLayout {
    static let shared = CreditsLayout()

    private var key: (tokens: [ScriptToken], width: CGFloat, fontSize: Double, tracking: CGFloat)?
    private var cached: [Range<Int>] = []

    func lines(for tokens: [ScriptToken], width: CGFloat, fontSize: Double, tracking: CGFloat) -> [Range<Int>] {
        if let key, key.width == width, key.fontSize == fontSize, key.tracking == tracking, key.tokens == tokens {
            return cached
        }
        let font = NSFont(name: Theme.Weight.medium.postScript, size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .medium)
        let text = NSMutableString()
        var tokenStarts: [Int] = []
        for token in tokens {
            tokenStarts.append(text.length)
            text.append(token.displayText)
        }
        let string = NSAttributedString(string: text as String, attributes: [.font: font, .kern: tracking])
        let typesetter = CTTypesetterCreateWithAttributedString(string)
        var lineStarts: [Int] = []
        var position = 0
        // A little slack so SwiftUI's rendering never needs more room than CoreText measured.
        let lineWidth = Double(max(width - 4, 40))
        while position < string.length {
            lineStarts.append(position)
            position += max(CTTypesetterSuggestLineBreak(typesetter, position, lineWidth), 1)
        }

        var result: [Range<Int>] = []
        var line = 0
        var lineStart = 0
        for (index, start) in tokenStarts.enumerated() {
            var next = line
            while next + 1 < lineStarts.count, lineStarts[next + 1] <= start { next += 1 }
            if next != line {
                if index > lineStart { result.append(lineStart..<index) }
                lineStart = index
                line = next
            }
        }
        if lineStart < tokens.count { result.append(lineStart..<tokens.count) }

        key = (tokens, width, fontSize, tracking)
        cached = result
        return result
    }
}

/// Black shape that flows out of the notch: concave top shoulders, rounded bottom.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topRadius, rect.width / 4)
        let bottom = min(bottomRadius, rect.height / 2, (rect.width - 2 * top) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Click to pause/resume, scroll to nudge the position word by word.
private struct EventCatcher: NSViewRepresentable {
    var onClick: () -> Void
    var onScroll: (Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onClick: (() -> Void)?
        var onScroll: ((Int) -> Void)?
        private var accumulated: CGFloat = 0

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseUp(with event: NSEvent) {
            onClick?()
        }

        override func scrollWheel(with event: NSEvent) {
            accumulated += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 12)
            let step: CGFloat = 22
            while accumulated <= -step { accumulated += step; onScroll?(1) }
            while accumulated >= step { accumulated -= step; onScroll?(-1) }
            if event.phase == .ended || event.momentumPhase == .ended { accumulated = 0 }
        }
    }
}
