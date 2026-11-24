import AVFoundation
import Speech
import SidekickCore

/// Streams the microphone into Apple's speech recognizer (on-device when available)
/// and reports the words heard since the current recognition segment began.
@MainActor
final class SpeechFollower: ObservableObject {
    enum State: Equatable {
        case idle
        case listening
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var isOnDevice = false

    /// All words recognized since the current segment started (revisions included).
    var onWords: (([String]) -> Void)?
    /// A new recognition segment started; word counts restart from zero.
    var onSegmentStart: (() -> Void)?
    var onFailure: ((String) -> Void)?

    var localeIdentifier = "en-US"
    var contextualStrings: [String] = [] {
        didSet {
            if #available(macOS 26.0, *), let analyzer = analyzer as? SpeechAnalyzer {
                let context = Self.context(for: contextualStrings)
                Task { try? await analyzer.setContext(context) }
            }
        }
    }

    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var rotateTimer: Timer?
    private var generation = 0
    private var recentFailures: [Date] = []
    private var configObserver: NSObjectProtocol?
    private var lastWords: [String] = []

    // On macOS 26, SpeechAnalyzer takes over from SFSpeechRecognizer once its model is ready.
    private var session = 0
    private var analyzer: AnyObject?
    private var analyzerFeed: AnyObject?
    private var analyzerTask: Task<Void, Never>?
    private var finalWords: [String] = []
    private var volatileWords: [String] = []
    private var segmentStartSeconds: Double = 0

    /// Segments are rotated before Apple's ~1 minute per-request limit.
    private let segmentLength: TimeInterval = 50

    static func requestPermissions() async -> String? {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return "Allow Speech Recognition for Sidekick in System Settings → Privacy & Security."
        }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard mic else {
            return "Allow Microphone access for Sidekick in System Settings → Privacy & Security."
        }
        return nil
    }

    func start() throws {
        guard state == .idle else { return }
        let locale = Locale(identifier: localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            throw FollowerError.recognizerUnavailable
        }
        self.recognizer = recognizer
        isOnDevice = recognizer.supportsOnDeviceRecognition

        // With no input device the node still reports a 2ch output format, but installTap raises
        // an Objective-C exception, so check for a device and a valid hardware format first.
        guard AVCaptureDevice.default(for: .audio) != nil else { throw FollowerError.noMicrophone }
        let input = engine.inputNode
        let hardware = input.inputFormat(forBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard hardware.channelCount > 0, hardware.sampleRate > 0,
              format.channelCount > 0, format.sampleRate > 0 else { throw FollowerError.noMicrophone }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTap(box: box, owner: self))
        engine.prepare()
        try engine.start()

        state = .listening
        recentFailures = []
        observeConfigurationChanges()
        beginSegment()
        if #available(macOS 26.0, *) { startAnalyzer(locale: locale, inputFormat: format) }
    }

    func stop() {
        generation += 1
        session += 1
        stopAnalyzer()
        rotateTimer?.invalidate()
        rotateTimer = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        box.request?.endAudio()
        box.request = nil
        task?.cancel()
        task = nil
        state = .idle
        level = 0
    }

    /// Starts a fresh recognition segment (used after the script position jumps).
    func restartSegment() {
        guard state == .listening else { return }
        if #available(macOS 26.0, *), let feed = analyzerFeed as? AnalyzerFeed {
            return beginAnalyzerSegment(at: feed.seconds)
        }
        beginSegment()
    }

    private func beginSegment() {
        guard let recognizer else { return }
        generation += 1
        let current = generation

        box.request?.endAudio()
        task?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.contextualStrings = contextualStrings
        box.request = request

        lastWords = []
        onSegmentStart?()
        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler(owner: self, generation: current))

        rotateTimer?.invalidate()
        rotateTimer = Timer.scheduledTimer(withTimeInterval: segmentLength, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartSegment() }
        }
    }

    fileprivate func handle(generation: Int, words: [String], isFinal: Bool, error: Error?) {
        guard generation == self.generation, state == .listening else { return }
        if !words.isEmpty {
            // After a pause, macOS 26 starts a new utterance inside the same task: the transcript
            // drops back to just the new words without a final result. Treat that as a new segment.
            if Utterance.isNew(words, after: lastWords) { onSegmentStart?() }
            lastWords = words
            onWords?(words)
        }
        guard isFinal || error != nil else { return }

        if let error, words.isEmpty, !Self.isBenign(error) {
            let now = Date()
            recentFailures = recentFailures.filter { now.timeIntervalSince($0) < 10 } + [now]
            if recentFailures.count >= 5 {
                stop()
                onFailure?("Speech recognition stopped: \(error.localizedDescription)")
                return
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.restartSegment()
            }
        }
    }

    @available(macOS 26.0, *)
    private func startAnalyzer(locale: Locale, inputFormat: AVAudioFormat) {
        let id = session
        let hints = contextualStrings
        analyzerTask = Task { [weak self] in
            guard SpeechTranscriber.isAvailable,
                  let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { return }
            let transcriber = SpeechTranscriber(
                locale: supported, transcriptionOptions: [],
                reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
            do {
                guard await AssetInventory.status(forModules: [transcriber]) != .unsupported else { return }
                _ = try? await AssetInventory.reserve(locale: supported)
                // The first time, this downloads Apple's speech model while the older recognizer keeps listening.
                if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    try await install.downloadAndInstall()
                }
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber], considering: inputFormat) else { return }
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                try await analyzer.setContext(Self.context(for: hints))
                try await analyzer.prepareToAnalyze(in: format)
                let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
                guard let feed = AnalyzerFeed(from: inputFormat, to: format, continuation: continuation),
                      let self, self.session == id, self.state == .listening
                else { await analyzer.cancelAndFinishNow(); return }
                self.switchToAnalyzer(analyzer, feed: feed)
                try await analyzer.start(inputSequence: stream)
                for try await result in transcriber.results {
                    guard self.session == id else { break }
                    self.handle(result)
                }
            } catch {
                guard let self, self.session == id, self.state == .listening, self.analyzer != nil else { return }
                // Fall back to the older recognizer for the rest of this session.
                self.stopAnalyzer()
                self.beginSegment()
            }
        }
    }

    @available(macOS 26.0, *)
    private func switchToAnalyzer(_ analyzer: SpeechAnalyzer, feed: AnalyzerFeed) {
        generation += 1
        rotateTimer?.invalidate()
        rotateTimer = nil
        box.request?.endAudio()
        task?.cancel()
        task = nil
        self.analyzer = analyzer
        analyzerFeed = feed
        box.setFeed(feed.append)
        isOnDevice = true
        beginAnalyzerSegment(at: feed.seconds)
    }

    @available(macOS 26.0, *)
    private func beginAnalyzerSegment(at seconds: Double) {
        finalWords = []
        volatileWords = []
        lastWords = []
        segmentStartSeconds = seconds
        onSegmentStart?()
    }

    @available(macOS 26.0, *)
    private func handle(_ result: SpeechTranscriber.Result) {
        guard state == .listening, result.range.end.seconds > segmentStartSeconds else { return }
        let words = String(result.text.characters)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        if result.isFinal {
            finalWords += words
            volatileWords = []
        } else {
            volatileWords = words
        }
        let all = finalWords + volatileWords
        guard !all.isEmpty else { return }
        lastWords = all
        onWords?(all)
        // Keep segments short, like the older recognizer's, so word counts stay small.
        if result.isFinal, finalWords.count > 150 { beginAnalyzerSegment(at: result.range.end.seconds) }
    }

    private func stopAnalyzer() {
        analyzerTask?.cancel()
        analyzerTask = nil
        box.setFeed(nil)
        if #available(macOS 26.0, *) {
            (analyzerFeed as? AnalyzerFeed)?.finish()
            if let analyzer = analyzer as? SpeechAnalyzer { Task { await analyzer.cancelAndFinishNow() } }
        }
        analyzer = nil
        analyzerFeed = nil
    }

    @available(macOS 26.0, *)
    private static func context(for hints: [String]) -> AnalysisContext {
        let context = AnalysisContext()
        context.contextualStrings[.general] = hints
        return context
    }

    fileprivate func updateLevel(_ value: Float) {
        let smoothed = level * 0.6 + value * 0.4
        if abs(smoothed - level) > 0.02 || (smoothed == 0) != (level == 0) { level = smoothed }
    }

    private func observeConfigurationChanges() {
        guard configObserver == nil else { return }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .listening else { return }
                self.stop()
                try? self.start()
            }
        }
    }

    private static func isBenign(_ error: Error) -> Bool {
        let nsError = error as NSError
        // 1110: no speech detected, 216/301: request cancelled/ended.
        return [1110, 216, 301, 203].contains(nsError.code)
    }

    private nonisolated static func makeTap(box: RequestBox, owner: SpeechFollower) -> AVAudioNodeTapBlock {
        var counter = 0
        return { [weak owner] buffer, _ in
            box.append(buffer)
            counter += 1
            guard counter % 4 == 0 else { return }
            let level = normalizedLevel(buffer)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { owner?.updateLevel(level) }
            }
        }
    }

    private nonisolated static func makeResultHandler(owner: SpeechFollower, generation: Int) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        return { [weak owner] result, error in
            let words = result?.bestTranscription.segments.map(\.substring) ?? []
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    owner?.handle(generation: generation, words: words, isFinal: isFinal, error: error)
                }
            }
        }
    }

    private nonisolated static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = (sum / Float(count)).squareRoot()
        let db = 20 * log10(max(rms, 0.000_01))
        return min(max((db + 50) / 45, 0), 1)
    }
}

enum FollowerError: LocalizedError {
    case recognizerUnavailable
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognition isn't available for this language right now."
        case .noMicrophone: return "No microphone input found."
        }
    }
}

/// Hands audio buffers from the realtime tap thread to the current recognition request.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: SFSpeechAudioBufferRecognitionRequest?
    private var feed: ((AVAudioPCMBuffer) -> Void)?

    func setFeed(_ newValue: ((AVAudioPCMBuffer) -> Void)?) {
        lock.lock(); feed = newValue; lock.unlock()
    }

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.lock(); defer { lock.unlock() }; return _request }
        set { lock.lock(); _request = newValue; lock.unlock() }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if let feed { feed(buffer) } else { _request?.append(buffer) }
        lock.unlock()
    }
}

/// Converts microphone buffers to the analyzer's format and streams them in, counting the audio fed.
@available(macOS 26.0, *)
private final class AnalyzerFeed: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let format: AVAudioFormat
    private let continuation: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var frames: Int64 = 0

    init?(from input: AVAudioFormat, to format: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation) {
        if input == format {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: input, to: format) else { return nil }
            self.converter = converter
        }
        self.format = format
        self.continuation = continuation
    }

    var seconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(frames) / format.sampleRate
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        var output = buffer
        if let converter {
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, converted.frameLength > 0 else { return }
            output = converted
        }
        lock.lock(); frames += Int64(output.frameLength); lock.unlock()
        continuation.yield(AnalyzerInput(buffer: output))
    }

    func finish() { continuation.finish() }
}
