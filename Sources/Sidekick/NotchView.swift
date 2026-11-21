import AppKit
import SidekickCore
import SwiftUI

struct NotchView: View {
    @EnvironmentObject private var prompter: Prompter
    @EnvironmentObject private var geometry: NotchGeometry
    @AppStorage(Prefs.fontSize) private var fontSize = 18.0
    @AppStorage(Prefs.lineCount) private var lineCount = 2
    @AppStorage(Prefs.panelWidth) private var panelWidth = 620.0
    @AppStorage(Prefs.showSpoken) private var showSpoken = false

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
                Text(progressLabel)
                    .font(Theme.intern(11, .medium))
                    .monospacedDigit()
                    .foregroundColor(Theme.secondary)
            }
            .padding(.horizontal, 26)
            .frame(height: geometry.notchSize.height)

            PromptText(
                tokens: prompter.tokens,
                cursor: prompter.cursor,
                fontSize: fontSize,
                lines: lineCount,
                showSpoken: showSpoken
            )
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

    private var progressLabel: String {
        "\(Int((prompter.progress * 100).rounded()))%"
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

/// The script from the next word on. Spoken words fall away; the next word is brightest.
private struct PromptText: View {
    let tokens: [ScriptToken]
    let cursor: Int
    let fontSize: Double
    let lines: Int
    let showSpoken: Bool

    var body: some View {
        styledText
            .font(Theme.intern(fontSize, .medium))
            .tracking(fontSize >= 22 ? -0.2 : 0)
            .lineSpacing(fontSize * (NotchLayout.lineHeightMultiple - 1.2))
            .lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: cursor)
    }

    private var styledText: Text {
        guard !tokens.isEmpty else {
            return Text("Paste a script in Sidekick to begin.").foregroundColor(Theme.secondary)
        }
        guard cursor < tokens.count else {
            return Text("That's a wrap.").foregroundColor(Theme.secondary)
        }

        var text = Text("")
        if showSpoken {
            for token in tokens[max(0, cursor - 3)..<cursor] {
                text = text + Text(token.displayText).foregroundColor(Color(white: 0.28))
            }
        }

        var inFirstSentence = true
        let upcoming = tokens[cursor..<min(tokens.count, cursor + 80)]
        for (offset, token) in upcoming.enumerated() {
            let color: Color
            if offset == 0 {
                color = .white
            } else if inFirstSentence {
                color = Color(white: 0.74)
            } else {
                color = Color(white: 0.44)
            }
            text = text + Text(token.displayText).foregroundColor(color)
            if token.endsSentence { inFirstSentence = false }
        }
        return text
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
