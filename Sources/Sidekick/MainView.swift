import Carbon.HIToolbox
import Speech
import SidekickCore
import SwiftUI

struct MainView: View {
    enum Tab: String, CaseIterable {
        case script = "Script"
        case checklist = "Checklist"
        case settings = "Settings"
    }

    @EnvironmentObject private var prompter: Prompter
    @State private var tab: Tab = Prefs.defaults.string(forKey: Prefs.mode) == PromptMode.checklist.rawValue ? .checklist : .script

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            Group {
                switch tab {
                case .script: ScriptPane()
                case .checklist: ChecklistPane()
                case .settings: SettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 600, height: 640)
        .background(Theme.canvas)
        .preferredColorScheme(.dark)
        .tint(Theme.text)
        .onAppear { WindowPrivacy.apply() }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sidekick")
                    .font(Theme.display(26))
                    .tracking(-0.3)
                    .foregroundColor(Theme.text)
                Text("Your lines, in the notch.")
                    .font(Theme.intern(13))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 18) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button(item.rawValue) { select(item) }
                        .buttonStyle(TabButtonStyle(isActive: tab == item))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 16)
    }

    /// ⌥⌘P starts whichever of Script or Checklist you last had open.
    private func select(_ item: Tab) {
        tab = item
        let mode: PromptMode? = item == .script ? .script : item == .checklist ? .checklist : nil
        if let mode { Prefs.defaults.set(mode.rawValue, forKey: Prefs.mode) }
    }
}

private struct TabButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.intern(13, isActive ? .medium : .regular))
            .foregroundColor(isActive ? Theme.text : Theme.secondary)
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                Rectangle().fill(isActive ? Theme.text : .clear).frame(height: 1)
            }
            .contentShape(Rectangle())
    }
}

// MARK: Script

private struct ScriptPane: View {
    @EnvironmentObject private var prompter: Prompter
    @AppStorage(Prefs.script) private var script = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $script)
                    .font(Theme.intern(15))
                    .lineSpacing(5)
                    .foregroundColor(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                if script.isEmpty {
                    Text("Paste your video script here. Sidekick listens as you speak and keeps the next words in your notch.")
                        .font(Theme.intern(15))
                        .lineSpacing(5)
                        .foregroundColor(Theme.tertiary)
                        .padding(.horizontal, 17)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline, lineWidth: 1))

            if let message = prompter.message {
                Text(message)
                    .font(Theme.intern(12))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.raised))
            }

            PresentControls(mode: .script, stats: stats, isEmpty: script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(28)
        .onChange(of: script) { newValue in
            if prompter.isPresenting, prompter.mode == .script { prompter.load(newValue) }
        }
    }

    private var stats: String {
        let words = script.split(whereSeparator: \.isWhitespace).count
        guard words > 0 else { return "0 words" }
        let minutes = max(1, Int((Double(words) / 150).rounded()))
        if prompter.isPresenting, prompter.mode == .script {
            return "\(words) words · \(Int((prompter.progress * 100).rounded()))% read"
        }
        return "\(words) words · ~\(minutes) min"
    }
}

// MARK: Checklist

private struct ChecklistPane: View {
    @EnvironmentObject private var prompter: Prompter
    @AppStorage(Prefs.checklist) private var checklist = ""
    @State private var rows: [ChecklistRow] = []
    @State private var editingAsText = false
    @State private var hovered: UUID?
    @FocusState private var focused: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(editingAsText ? "One item per line" : "Talking points, in order")
                    .font(Theme.intern(12, .medium))
                    .foregroundColor(Theme.secondary)
                Spacer()
                Button(editingAsText ? "Edit as list" : "Edit as text") { editingAsText.toggle() }
                    .buttonStyle(GhostButtonStyle())
            }

            Group {
                if editingAsText { textEditor } else { list }
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline, lineWidth: 1))

            switch ChecklistJudge.status {
            case .ready:
                Text("Understands paraphrasing with Apple Intelligence, on this Mac. ⌥⌘→ ticks an item off by hand.")
                    .font(Theme.intern(12))
                    .foregroundColor(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .unavailable(let reason):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Intelligence isn't available")
                        .font(Theme.intern(12, .medium))
                        .foregroundColor(Theme.text)
                    Text(reason + " Say the item's key words, or press ⌥⌘→ to tick it off by hand.")
                        .font(Theme.intern(12))
                        .foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.text.opacity(0.5), lineWidth: 1))
            }

            if let message = prompter.message {
                Text(message)
                    .font(Theme.intern(12))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.raised))
            }

            PresentControls(mode: .checklist, stats: stats, isEmpty: ChecklistParser.items(from: checklist).isEmpty)
        }
        .padding(28)
        .onAppear(perform: syncRows)
        .onChange(of: checklist) { newValue in
            syncRows()
            if prompter.isPresenting, prompter.mode == .checklist { prompter.loadChecklist(newValue) }
        }
        .onChange(of: rows) { _ in rowsChanged() }
    }

    private var textEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $checklist)
                .font(Theme.intern(15))
                .lineSpacing(5)
                .foregroundColor(Theme.text)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            if checklist.isEmpty {
                Text("Paste your list here, one item per line. Bullets and numbers are fine.")
                    .font(Theme.intern(15))
                    .lineSpacing(5)
                    .foregroundColor(Theme.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                rowStack
            }
            .onChange(of: focused) { id in
                if let id { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) } }
            }
        }
    }

    private var rowStack: some View {
        VStack(spacing: 0) {
            ForEach($rows) { $row in
                rowView($row).id(row.id)
                Rectangle().fill(Theme.hairline).frame(height: 1)
            }
            Button(action: { addRow(after: rows.last?.id) }) {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 16, height: 16)
                    Text("Add item").font(Theme.intern(14))
                    Spacer()
                }
                .foregroundColor(Theme.tertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func rowView(_ row: Binding<ChecklistRow>) -> some View {
        let id = row.wrappedValue.id
        let item = itemIndex(of: id)
        let live = prompter.isPresenting && prompter.mode == .checklist
        let done = live && item.map { $0 < prompter.itemCursor || $0 == prompter.checkingItem } == true
        let current = live && item == prompter.itemCursor && prompter.checkingItem == nil

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button {
                if let item { prompter.checkItems(before: done ? item : item + 1) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(done ? Theme.text : .clear)
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(done ? Theme.text : current ? Theme.secondary : Theme.tertiary, lineWidth: 1)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.canvas)
                    }
                }
                .frame(width: 16, height: 16)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            }
            .buttonStyle(.plain)
            .disabled(!live || item == nil)
            .help(live ? (done ? "Untick" : "Tick off") : "Ticks off as you talk")

            TextField("Talking point", text: row.text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.intern(15))
                .foregroundColor(done ? Theme.tertiary : Theme.text)
                .strikethrough(done, color: Theme.tertiary)
                .focused($focused, equals: id)
                .onSubmit { addRow(after: id) }

            if current {
                Text("NOW")
                    .font(Theme.mono(10))
                    .foregroundColor(Theme.secondary)
            }
            Button { remove(id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.tertiary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered == id ? 1 : 0)
            .help("Remove")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(current ? Theme.raised : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? id : (hovered == id ? nil : hovered) }
    }

    /// The row's position among non-empty rows, which is its index in the notch.
    private func itemIndex(of id: UUID) -> Int? {
        guard let row = rows.firstIndex(where: { $0.id == id }), !rows[row].isBlank else { return nil }
        return rows[..<row].filter { !$0.isBlank }.count
    }

    private var serialized: String {
        rows.filter { !$0.isBlank }.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
    }

    private func syncRows() {
        guard ChecklistParser.items(from: checklist) != ChecklistParser.items(from: serialized) || rows.isEmpty else { return }
        rows = ChecklistParser.items(from: checklist).map { ChecklistRow(text: $0) }
        if rows.isEmpty { rows = [ChecklistRow(text: "")] }
    }

    private func rowsChanged() {
        // A pasted list arrives as one row with line breaks; split it into rows.
        if let index = rows.firstIndex(where: { $0.text.contains("\n") }) {
            let pieces = ChecklistParser.items(from: rows[index].text).map { ChecklistRow(text: $0) }
            rows.replaceSubrange(index...index, with: pieces.isEmpty ? [ChecklistRow(text: "")] : pieces)
            focused = rows[min(index + max(pieces.count, 1), rows.count) - 1].id
            return
        }
        if serialized != checklist { checklist = serialized }
    }

    private func addRow(after id: UUID?) {
        if let id, let index = rows.firstIndex(where: { $0.id == id }) {
            if rows[index].isBlank { return }
            if index + 1 < rows.count, rows[index + 1].isBlank { focused = rows[index + 1].id; return }
            let row = ChecklistRow(text: "")
            rows.insert(row, at: index + 1)
            focused = row.id
        } else {
            let row = ChecklistRow(text: "")
            rows.append(row)
            focused = row.id
        }
    }

    private func remove(_ id: UUID) {
        rows.removeAll { $0.id == id }
        if rows.isEmpty { rows = [ChecklistRow(text: "")] }
    }

    private var stats: String {
        let count = ChecklistParser.items(from: checklist).count
        if prompter.isPresenting, prompter.mode == .checklist {
            return "\(prompter.progressLabel) covered"
        }
        return count == 1 ? "1 item" : "\(count) items"
    }
}

private struct ChecklistRow: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// Stats on the left; Start, or Stop · Restart · Pause while this mode is in the notch.
private struct PresentControls: View {
    @EnvironmentObject private var prompter: Prompter
    let mode: PromptMode
    let stats: String
    let isEmpty: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(stats)
                .font(Theme.mono(11))
                .foregroundColor(Theme.tertiary)
            Spacer()
            if prompter.isPresenting, prompter.mode == mode {
                Button("Stop") { prompter.stop() }
                    .buttonStyle(GhostButtonStyle())
                    .padding(.trailing, 6)
                Button("Restart") { prompter.restart() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(prompter.isListening ? "Pause" : "Resume") { prompter.primaryAction() }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    prompter.present(mode)
                } label: {
                    HStack(spacing: 8) {
                        Text("Start in notch")
                        Text("⌥⌘P").font(Theme.mono(11)).opacity(0.5)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isEmpty)
            }
        }
    }
}

// MARK: Settings

private struct SettingsPane: View {
    @AppStorage(Prefs.hideFromCapture) private var hideFromCapture = true
    @AppStorage(Prefs.fontSize) private var fontSize = 18.0
    @AppStorage(Prefs.lineCount) private var lineCount = 2
    @AppStorage(Prefs.panelWidth) private var panelWidth = 620.0
    @AppStorage(Prefs.localeID) private var localeID = Prefs.defaultLocaleID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SettingsSection("Privacy") {
                    SettingRow("Hide from screen recordings",
                               caption: "You see Sidekick; recordings, screenshots and screen shares don't. Turn off to show it in a demo. Shortcut below.") {
                        Toggle("", isOn: $hideFromCapture).toggleStyle(MonoSwitchStyle())
                    }
                }

                SettingsSection("Notch") {
                    SettingRow("Text size", caption: "\(Int(fontSize)) pt") {
                        Slider(value: $fontSize, in: 13...30, step: 1).frame(width: 180)
                    }
                    SettingRow("Width", caption: "\(Int(panelWidth)) pt") {
                        Slider(value: $panelWidth, in: 440...1000, step: 10).frame(width: 180)
                    }
                    SettingRow("Lines", caption: "Lines in full view. The next one peeks in, faded, below.") {
                        Stepper(value: $lineCount, in: 1...4) {
                            Text("\(lineCount)")
                                .font(Theme.intern(13, .medium))
                                .monospacedDigit()
                                .foregroundColor(Theme.text)
                        }
                    }
                }

                SettingsSection("Listening") {
                    SettingRow("Language", caption: "Recognition runs on-device when your Mac supports it.") {
                        Picker("", selection: $localeID) {
                            ForEach(Self.locales) { locale in
                                Text(locale.name).tag(locale.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                }

                SettingsSection("Shortcuts") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Hide · show in recordings")
                                .font(Theme.intern(13))
                                .foregroundColor(Theme.text)
                            Spacer()
                            ShortcutRecorder()
                        }
                        ForEach(HotKeys.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.action)
                                    .font(Theme.intern(13))
                                    .foregroundColor(Theme.text)
                                Spacer()
                                Text(shortcut.keys)
                                    .font(Theme.mono(12))
                                    .foregroundColor(Theme.secondary)
                            }
                        }
                        Text("Click the notch to pause or resume. Scroll over it to nudge word by word.")
                            .font(Theme.intern(12))
                            .foregroundColor(Theme.tertiary)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(28)
        }
    }

    private struct LanguageOption: Identifiable {
        let id: String
        let name: String
    }

    private static let locales: [LanguageOption] = {
        let current = Locale.current
        return SFSpeechRecognizer.supportedLocales()
            .map { locale in
                let id = locale.identifier.replacingOccurrences(of: "_", with: "-")
                return LanguageOption(id: id, name: current.localizedString(forIdentifier: locale.identifier) ?? id)
            }
            .sorted { $0.name < $1.name }
    }()
}

/// Click, then press a new key combo. Esc cancels; ⌫ clears.
private struct ShortcutRecorder: View {
    @AppStorage(Prefs.privacyKeyCode) private var keyCode = PrivacyShortcut.defaultCombo.keyCode
    @AppStorage(Prefs.privacyLabel) private var label = PrivacyShortcut.defaultCombo.label
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { recording ? stop() : start() }) {
            Text(recording ? "Press keys…" : keyCode < 0 ? "None" : label)
                .font(Theme.mono(12))
                .foregroundColor(recording ? Theme.text : Theme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .stroke(recording ? Theme.text : Theme.hairline, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to change. Esc cancels, Delete clears.")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        PrivacyShortcut.suspend()
        HotKeyCenter.shared.isPaused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = Int(event.keyCode)
            if let combo = PrivacyShortcut.combo(from: event) {
                if !PrivacyShortcut.set(combo) { NSSound.beep() }
                stop()
            } else if key == kVK_Escape {
                stop()
            } else if key == kVK_Delete || key == kVK_ForwardDelete {
                PrivacyShortcut.set(nil)
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        HotKeyCenter.shared.isPaused = false
        PrivacyShortcut.register()
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(Theme.mono(11))
                .tracking(0.6)
                .foregroundColor(Theme.tertiary)
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.radius).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hairline, lineWidth: 1))
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder let control: Control

    init(_ title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.intern(13, .medium))
                    .foregroundColor(Theme.text)
                if let caption {
                    Text(caption)
                        .font(Theme.intern(12))
                        .foregroundColor(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 10)
    }
}
