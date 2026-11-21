import AppKit
import Combine
import SwiftUI

/// Measures the notch of the display Sidekick lives on.
@MainActor
final class NotchGeometry: ObservableObject {
    @Published private(set) var notchSize = CGSize(width: 190, height: 32)
    @Published private(set) var hasNotch = false
    private(set) var screenFrame: CGRect = .zero

    static var preferredScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    func update(for screen: NSScreen) {
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
            hasNotch = true
        } else {
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            notchSize = CGSize(width: 190, height: max(24, menuBar))
            hasNotch = false
        }
    }

    /// Size of the open teleprompter, including the strip beside the camera.
    func expandedSize(width: Double, fontSize: Double, lines: Int) -> CGSize {
        let minWidth = notchSize.width + 200
        let w = min(max(CGFloat(width), minWidth), max(screenFrame.width - 40, minWidth))
        let lineHeight = CGFloat(fontSize) * NotchLayout.lineHeightMultiple
        let textHeight = lineHeight * CGFloat(max(lines, 1))
        return CGSize(width: w.rounded(), height: (notchSize.height + NotchLayout.textTopPadding + textHeight + NotchLayout.bottomPadding).rounded())
    }
}

enum NotchLayout {
    static let lineHeightMultiple: CGFloat = 1.38
    static let textTopPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 16
    static let canvas = CGSize(width: 1100, height: 420)
}

final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NotchLayout.canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the notch panel, keeps it pinned to the top of the notched display and only
/// accepts mouse events while the pointer is over the visible black shape.
@MainActor
final class NotchController {
    private let panel = NotchPanel()
    private let prompter: Prompter
    private let geometry = NotchGeometry()
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    init(prompter: Prompter) {
        self.prompter = prompter
        let root = NotchView()
            .environmentObject(prompter)
            .environmentObject(prompter.speech)
            .environmentObject(geometry)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: NotchLayout.canvas)
        panel.contentView = host
        panel.sharingType = WindowPrivacy.sharingType

        reposition()
        panel.orderFrontRegardless()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
        prompter.$isPresenting
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateMouseHandling() } }
            .store(in: &cancellables)

        let handler: () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.updateMouseHandling() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { _ in handler() }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in handler(); return event }) {
            monitors.append(local)
        }
    }

    private func reposition() {
        guard let screen = NotchGeometry.preferredScreen else { return }
        geometry.update(for: screen)
        let size = NotchLayout.canvas
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func updateMouseHandling() {
        guard prompter.isPresenting else {
            panel.ignoresMouseEvents = true
            return
        }
        let defaults = Prefs.defaults
        let size = geometry.expandedSize(
            width: defaults.double(forKey: Prefs.panelWidth),
            fontSize: defaults.double(forKey: Prefs.fontSize),
            lines: defaults.integer(forKey: Prefs.lineCount)
        )
        let frame = geometry.screenFrame
        let shape = CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
        let inside = shape.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }
}
