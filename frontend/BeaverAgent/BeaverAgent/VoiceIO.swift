import AVFoundation

/// Mic and speaker on one `AVAudioEngine`, per contracts § Audio: `.playAndRecord` with
/// `.defaultToSpeaker`, voice processing (echo cancellation) on, the mic converted to
/// Int16 24 kHz mono and cut into 80 ms chunks, TTS chunks played back to back on an
/// `AVAudioPlayerNode`. The session decides which mic chunks go on the wire.
@MainActor
final class VoiceIO {
    nonisolated static let sampleRate = 24_000.0
    /// 80 ms = 1920 samples = 3840 bytes.
    nonisolated static let chunkBytes = 3840

    /// One 80 ms mic chunk, base64, ready for an `audio` frame.
    var onChunk: (String) -> Void = { _ in }
    /// TTS audio started or stopped being queued.
    var onPlayingChange: (Bool) -> Void = { _ in }
    /// Something the user should know, e.g. no mic permission.
    var onProblem: (String) -> Void = { _ in }

    private(set) var isRunning = false
    /// The engine has a mic (or a `-micFile`); without one it still plays TTS.
    private(set) var hasMic = false
    private(set) var isPlaying = false {
        didSet { if isPlaying != oldValue { onPlayingChange(isPlaying) } }
    }

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let playFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: VoiceIO.sampleRate, channels: 1, interleaved: false
    )!
    private var wanted = false
    private var starting = false
    private var observers: [NSObjectProtocol] = []
    private var configObserver: NSObjectProtocol?

    /// Buffers scheduled on the player and not played back yet.
    private var queued = 0
    /// Bumped on every stop, so callbacks of dropped buffers are ignored.
    private var playGeneration = 0
    /// The server sent `audio_end` for the reply being played.
    private var speechEnded = true
    private var underruns = 0
    /// Played back for the current reply, for the log line at its end.
    private var playedSeconds = 0.0
    private var playedChunks = 0

    /// `-micFile name.wav` (in the app's Documents): stream that file instead of the mic,
    /// for the Simulator on a Mac without an audio input.
    private var fileSource: FileMicSource?

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated {
                if type == .ended { self?.restart(reason: "interruption ended") }
            }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart(reason: "media services reset") }
        })
    }

    // MARK: - Engine

    /// Asks for the mic, sets up the session and starts the engine. Safe to call again.
    func start() {
        wanted = true
        guard !isRunning, !starting else { return }
        starting = true
        Task {
            defer { starting = false }
            guard await AVAudioApplication.requestRecordPermission() else {
                onProblem("Microphone access is off. Turn it on in the Settings app, or type a question.")
                return
            }
            guard wanted else { return }
            do {
                try build()
            } catch {
                print("voice: engine failed to start: \(error)")
                onProblem("Can't start the microphone.")
            }
        }
    }

    func stop() {
        wanted = false
        tearDown()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The app is back in the foreground: iOS may have stopped the engine meanwhile.
    func resume() {
        guard wanted, !starting else { return }
        if !isRunning || !engine.isRunning { restart(reason: "foreground") }
    }

    private func restart(reason: String) {
        guard wanted, !starting else { return }
        print("voice: restarting engine (\(reason))")
        tearDown()
        start()
    }

    private func build() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)

        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        let deliver = Self.deliverer(to: self)
        if let name = UserDefaults.standard.string(forKey: "micFile") {
            // The file replaces the input node entirely: the engine only plays.
            let url = URL.documentsDirectory.appending(path: name)
            fileSource = try FileMicSource(url: url, deliver: deliver)
            hasMic = true
            print("voice: mic is the file \(name)")
        } else {
            let input = engine.inputNode
            do {
                // Before reading the input format: voice processing changes it.
                try input.setVoiceProcessingEnabled(true)
                input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
            } catch {
                print("voice: voice processing unavailable: \(error)")
            }
            let format = input.outputFormat(forBus: 0)
            if format.channelCount > 0, format.sampleRate > 0, let converter = MicConverter(from: format) {
                print("voice: mic \(format)")
                input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.tap(converter: converter, deliver: deliver))
                hasMic = true
            } else {
                // A Mac without an audio input runs the Simulator this way. Playback still works.
                print("voice: no mic input (\(format)), playback only")
                try? input.setVoiceProcessingEnabled(false)
                onProblem("No microphone found. You can still type a question.")
            }
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Voice processing and route changes post this, often with the engine still
                // running; restarting then would only post it again.
                guard let self, !self.engine.isRunning else { return }
                self.restart(reason: "configuration change")
            }
        }

        engine.prepare()
        try engine.start()
        fileSource?.start()
        isRunning = true
    }

    private func tearDown() {
        stopPlayback()
        let tapped = hasMic && fileSource == nil
        fileSource?.stop()
        fileSource = nil
        if tapped { engine.inputNode.removeTap(onBus: 0) }
        if isRunning { engine.stop() }
        hasMic = false
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        isRunning = false
    }

    // MARK: - Playback

    /// A new reply's audio is about to arrive.
    func beginSpeech() {
        speechEnded = false
        underruns = 0
        playedSeconds = 0
        playedChunks = 0
    }

    /// Schedules one TTS `audio` chunk (base64 Int16 24 kHz mono) right after the last one.
    func play(base64: String) {
        guard isRunning, let buffer = Self.floatBuffer(fromBase64: base64, format: playFormat) else { return }
        queued += 1
        let seconds = Double(buffer.frameLength) / Self.sampleRate
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack, completionHandler: Self.played(by: self, generation: playGeneration, seconds: seconds))
        if !player.isPlaying { player.play() }
        isPlaying = true
    }

    /// The server sent `audio_end`: what is queued is the whole reply.
    func endSpeech() {
        speechEnded = true
        if queued == 0 { isPlaying = false }
    }

    /// Stops playback now and drops everything queued.
    func stopPlayback() {
        if queued > 0 { print(String(format: "voice: playback stopped after %.2f s, %d chunks dropped", playedSeconds, queued)) }
        playGeneration += 1
        if isRunning { player.stop() }
        queued = 0
        speechEnded = true
        isPlaying = false
    }

    private func bufferPlayed(generation: Int, seconds: Double) {
        guard generation == playGeneration else { return }
        queued = max(0, queued - 1)
        playedChunks += 1
        playedSeconds += seconds
        guard queued == 0 else { return }
        if speechEnded {
            print(String(format: "voice: reply played, %d chunks, %.2f s, %d underruns", playedChunks, playedSeconds, underruns))
            isPlaying = false
        } else {
            underruns += 1
            print("voice: playback underrun \(underruns): the queue ran dry before audio_end")
        }
    }

    // MARK: - Audio-thread helpers (nonisolated: they run off the main thread)

    private nonisolated static func deliverer(to voice: VoiceIO) -> @Sendable (Data) -> Void {
        { [weak voice] chunk in
            let text = chunk.base64EncodedString()
            DispatchQueue.main.async { MainActor.assumeIsolated { voice?.onChunk(text) } }
        }
    }

    private nonisolated static func tap(converter: MicConverter, deliver: @escaping @Sendable (Data) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in converter.convert(buffer).forEach(deliver) }
    }

    private nonisolated static func played(by voice: VoiceIO, generation: Int, seconds: Double) -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak voice] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { voice?.bufferPlayed(generation: generation, seconds: seconds) } }
        }
    }

    /// Int16 little-endian PCM → a Float32 buffer in `format`.
    nonisolated static func floatBuffer(fromBase64 base64: String, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let data = Data(base64Encoded: base64), data.count >= 2 else { return nil }
        let frames = data.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { raw in
            for i in 0..<frames {
                out[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768
            }
        }
        return buffer
    }
}

enum VoiceError: LocalizedError {
    case noInput
    var errorDescription: String? { "This audio can't be used as a microphone." }
}

/// Converts mic buffers to Int16 24 kHz mono and cuts them into 3840-byte chunks.
/// Used from one thread at a time (the tap's audio thread, or the file source's timer).
final class MicConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: VoiceIO.sampleRate, channels: 1, interleaved: true)!
    private var pending = Data()

    init?(from input: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = converter
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Data] {
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard buffer.frameLength > 0,
              let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return [] }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let samples = converted.int16ChannelData?[0] else {
            print("voice: mic conversion failed: \(String(describing: error))")
            return []
        }
        pending.append(Data(bytes: samples, count: Int(converted.frameLength) * 2))
        var chunks: [Data] = []
        while pending.count >= VoiceIO.chunkBytes {
            chunks.append(Data(pending.prefix(VoiceIO.chunkBytes)))
            pending.removeFirst(VoiceIO.chunkBytes)
        }
        return chunks
    }
}

/// Plays an audio file into the mic path in real time, looping, through the same
/// `MicConverter` as the real mic. Simulator rehearsals only (`-micFile`).
private final class FileMicSource: @unchecked Sendable {
    private let file: AVAudioFile
    private let converter: MicConverter
    private let deliver: @Sendable (Data) -> Void
    private let queue = DispatchQueue(label: "voice.file-mic")
    private var timer: DispatchSourceTimer?

    init(url: URL, deliver: @escaping @Sendable (Data) -> Void) throws {
        file = try AVAudioFile(forReading: url)
        guard let converter = MicConverter(from: file.processingFormat) else { throw VoiceError.noInput }
        self.converter = converter
        self.deliver = deliver
    }

    func start() {
        let frames = AVAudioFrameCount(file.processingFormat.sampleRate * 0.02)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(2))
        timer.setEventHandler { [self] in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return }
            if file.framePosition >= file.length { file.framePosition = 0 }
            try? file.read(into: buffer, frameCount: frames)
            converter.convert(buffer).forEach(deliver)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
