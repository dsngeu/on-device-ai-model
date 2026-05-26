import AVFoundation
import Foundation
import UIKit

enum RecorderInterruptionType: String {
    case interruptionPause = "INTERRUPTION_PAUSE"
    case interruptionResume = "INTERRUPTION_RESUME"
    case manualPause = "MANUAL_PAUSE"
    case manualResume = "MANUAL_RESUME"
    case autoResumeFailed = "AUTO_RESUME_FAILED"
    case fileSizeLimit = "FILE_SIZE_LIMIT"
    case appTerminate = "APP_TERMINATE"
}

struct RecorderInterruptionEvent {
    let type: RecorderInterruptionType
    let reason: String
}

enum NativeAudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case alreadyPaused
    case notPaused
    case permissionDenied
    case sessionSetupFailed(String)
    case engineStartFailed(String)
    case inputUnavailable
    case fileOpenFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No recording is in progress."
        case .alreadyPaused:
            return "The active recording is already paused."
        case .notPaused:
            return "The active recording is not paused."
        case .permissionDenied:
            return "Microphone permission was denied."
        case .sessionSetupFailed(let message):
            return "Could not configure the audio session: \(message)"
        case .engineStartFailed(let message):
            return "Could not start the audio engine: \(message)"
        case .inputUnavailable:
            return "The input node was unavailable."
        case .fileOpenFailed:
            return "Could not create or open the recording files."
        }
    }
}

final class NativeAudioRecorderService: NSObject {
    var onAmplitude: ((Double) -> Void)?
    var onChunkReady: ((URL) -> Void)?
    var onInterruption: ((RecorderInterruptionEvent) -> Void)?

    private let logger = PrintLogger.shared

    private let stateQueue = DispatchQueue(label: "debrief.recorder.state", attributes: .concurrent)
    private let audioQueue = DispatchQueue(label: "debrief.recorder.audio", qos: .userInitiated)
    private let fileQueue = DispatchQueue(label: "debrief.recorder.file")

    private var engine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private let bus: AVAudioNodeBus = 0

    private var audioFileHandle: FileHandle?
    private var chunkFileHandle: FileHandle?
    private var chunkFileURL: URL?
    private var chunkTimer: DispatchSourceTimer?
    private var currentFileURL: URL?
    private var chunkRootURL: URL?
    private var chunkSeconds = 30
    private var chunkBytesWritten: Int64 = 0
    private var bytesWritten: Int64 = 0
    private let maxFileSize: Int64 = 1 * 1024 * 1024 * 1024

    private var interruptionObserver: NSObjectProtocol?
    private var lifecycleObserverAdded = false

    private var _isRecording = false
    private var _isPausedByInterruption = false
    private var _isManuallyPaused = false
    private var _isResumeInProgress = false
    private var _isResumingFromInterruption = false
    private var resumeWaiters: [CheckedContinuation<Bool, Error>] = []
    private var manualResumeConfirmationTimer: DispatchSourceTimer?

    private var isResumingFromInterruption: Bool {
        get { stateQueue.sync { _isResumingFromInterruption } }
        set { stateQueue.sync(flags: .barrier) { _isResumingFromInterruption = newValue } }
    }

    private var sampleRate: Double = 16_000
    private var channels: Int = 1

    private var lastAmplitudeDispatchTime: UInt64 = 0
    private let amplitudeMinIntervalNs: UInt64 = 67_000_000

    private var isRecording: Bool {
        get { stateQueue.sync { _isRecording } }
        set { stateQueue.sync(flags: .barrier) { _isRecording = newValue } }
    }

    private var isPausedByInterruption: Bool {
        get { stateQueue.sync { _isPausedByInterruption } }
        set { stateQueue.sync(flags: .barrier) { _isPausedByInterruption = newValue } }
    }

    private var isManuallyPaused: Bool {
        get { stateQueue.sync { _isManuallyPaused } }
        set { stateQueue.sync(flags: .barrier) { _isManuallyPaused = newValue } }
    }

    private var isResumeInProgress: Bool {
        get { stateQueue.sync { _isResumeInProgress } }
        set { stateQueue.sync(flags: .barrier) { _isResumeInProgress = newValue } }
    }

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    func startRecording(segmentURL: URL, chunkRootURL: URL, chunkSeconds: Int = 30) throws {
        guard !isRecording else {
            throw NativeAudioRecorderError.alreadyRecording
        }

        logger.log("Recording starting — segment: \(segmentURL.path), chunkInterval: \(chunkSeconds)s")

        self.chunkRootURL = chunkRootURL
        self.chunkSeconds = chunkSeconds
        self.currentFileURL = segmentURL
        self.bytesWritten = 0
        self.chunkBytesWritten = 0

        try configureAudioSession()
        logger.log("Audio session configured")
        setupInterruptionHandling()
        setupLifecycleObserver()
        try prepareFiles(segmentURL: segmentURL, chunkRootURL: chunkRootURL)
        try startEngine()
        startChunking(rootURL: chunkRootURL, seconds: chunkSeconds)
        isRecording = true
        logger.log("Recording started ✓")
    }

    func pauseRecording() throws {
        guard isRecording else { throw NativeAudioRecorderError.notRecording }
        guard !isManuallyPaused else { throw NativeAudioRecorderError.alreadyPaused }

        logger.log("Recording pausing (manual)")
        isManuallyPaused = true
        inputNode?.removeTap(onBus: bus)
        engine?.stop()
        stopChunking()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        logger.log("Recording paused ✓")
        onInterruption?(RecorderInterruptionEvent(type: .manualPause, reason: "User manually paused recording"))
    }

    func resumeRecording() async throws -> Bool {
        guard isRecording else { throw NativeAudioRecorderError.notRecording }
        guard isPausedByInterruption || isManuallyPaused else { throw NativeAudioRecorderError.notPaused }

        logger.log("Recording resume requested")

        if isResumeInProgress {
            logger.log("Resume already in progress — awaiting confirmation")
            return try await awaitResumeConfirmation()
        }

        isResumeInProgress = true
        try configureAudioSession()
        logger.log("Audio session reconfigured for resume")
        if audioFileHandle == nil {
            try reopenAudioFileHandle()
        }

        guard let inputNode, let engine else {
            isResumeInProgress = false
            throw NativeAudioRecorderError.inputUnavailable
        }

        let inputFormat = inputNode.outputFormat(forBus: bus)
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false)
        if let targetFormat {
            converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }

        inputNode.removeTap(onBus: bus)
        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            isResumeInProgress = false
            throw NativeAudioRecorderError.engineStartFailed(error.localizedDescription)
        }

        return try await awaitResumeConfirmation()
    }

    func stopRecording() {
        logger.log("Recording stopping")
        stopChunking()
        stopRecordingInternal()
        logger.log("Recording stopped ✓")
    }

    func teardownForAppTermination() {
        guard isRecording else { return }
        logger.log("App terminating — flushing and closing recording files")
        inputNode?.removeTap(onBus: bus)
        engine?.stop()
        fileQueue.sync {
            try? audioFileHandle?.synchronize()
            try? audioFileHandle?.close()
            try? chunkFileHandle?.synchronize()
            try? chunkFileHandle?.close()
            audioFileHandle = nil
            chunkFileHandle = nil
        }
        isRecording = false
        logger.log("Recording files flushed for app termination ✓")
        onInterruption?(RecorderInterruptionEvent(type: .appTerminate, reason: "Application will terminate"))
    }

    func cleanup() {
        stopChunking()
        stopRecordingInternal()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        if lifecycleObserverAdded {
            NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification, object: nil)
            lifecycleObserverAdded = false
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .defaultToSpeaker, .mixWithOthers]
            )
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.02)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw NativeAudioRecorderError.sessionSetupFailed(error.localizedDescription)
        }
    }

    private func prepareFiles(segmentURL: URL, chunkRootURL: URL) throws {
        do {
            try FileManager.default.createDirectory(at: segmentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: chunkRootURL, withIntermediateDirectories: true)
            logger.log("Recording directories created — segment dir: \(segmentURL.deletingLastPathComponent().path), chunk dir: \(chunkRootURL.path)")
            if !FileManager.default.fileExists(atPath: segmentURL.path) {
                FileManager.default.createFile(atPath: segmentURL.path, contents: nil)
                logger.log("Segment file created: \(segmentURL.path)")
            }
            audioFileHandle = try FileHandle(forWritingTo: segmentURL)
            audioFileHandle?.seekToEndOfFile()
        } catch {
            logger.log("Failed to create recording files — \(error.localizedDescription)")
            throw NativeAudioRecorderError.fileOpenFailed
        }
    }

    private func reopenAudioFileHandle() throws {
        guard let currentFileURL else { throw NativeAudioRecorderError.fileOpenFailed }
        do {
            audioFileHandle = try FileHandle(forWritingTo: currentFileURL)
            audioFileHandle?.seekToEndOfFile()
        } catch {
            throw NativeAudioRecorderError.fileOpenFailed
        }
    }

    private func startEngine() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: bus)
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels), interleaved: false) else {
            throw NativeAudioRecorderError.engineStartFailed("Failed to create target format.")
        }

        self.engine = engine
        self.inputNode = inputNode
        self.targetFormat = targetFormat
        self.converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: bus, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
            logger.log("Audio engine started ✓ — input: \(inputFormat.sampleRate)Hz → target: \(sampleRate)Hz")
        } catch {
            logger.log("Audio engine failed to start — \(error.localizedDescription)")
            throw NativeAudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }

    private func stopRecordingInternal() {
        isRecording = false
        isPausedByInterruption = false
        isManuallyPaused = false
        isResumeInProgress = false
        cancelManualResumeConfirmationTimer()
        resolveResumeWaiters(.failure(NativeAudioRecorderError.notRecording))

        inputNode?.removeTap(onBus: bus)
        engine?.stop()

        fileQueue.sync {
            try? audioFileHandle?.synchronize()
            try? audioFileHandle?.close()
            try? chunkFileHandle?.synchronize()
            try? chunkFileHandle?.close()
            audioFileHandle = nil
            chunkFileHandle = nil
            chunkFileURL = nil
        }

        engine = nil
        inputNode = nil
        converter = nil
        targetFormat = nil
        currentFileURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handleAudioBuffer(_ inBuffer: AVAudioPCMBuffer) {
        guard isRecording else { return }

        if isResumeInProgress {
            let wasInterruptionResume = isResumingFromInterruption
            isResumeInProgress = false
            isPausedByInterruption = false
            isManuallyPaused = false
            isResumingFromInterruption = false
            cancelManualResumeConfirmationTimer()
            logger.log("Audio buffers received — recording resumed ✓")
            if let chunkRootURL {
                startChunking(rootURL: chunkRootURL, seconds: chunkSeconds)
            }
            if wasInterruptionResume {
                onInterruption?(RecorderInterruptionEvent(type: .interruptionResume, reason: "Recording resumed"))
            } else {
                onInterruption?(RecorderInterruptionEvent(type: .manualResume, reason: "User manually resumed recording"))
            }
            resolveResumeWaiters(.success(true))
        }

        guard let converter, let targetFormat else {
            return
        }

        let ratio = targetFormat.sampleRate / inBuffer.format.sampleRate
        let outFrames = AVAudioFrameCount(Double(inBuffer.frameLength) * ratio + 64)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outFrames) else {
            return
        }

        var conversionError: NSError?
        var fed = false
        let status = converter.convert(to: outBuffer, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return inBuffer
        }

        guard status != .error, conversionError == nil else {
            return
        }

        let frames = Int(outBuffer.frameLength)
        guard frames > 0, let channelsData = outBuffer.floatChannelData else {
            return
        }

        let monoSamples = channelsData[0]
        var pcm16 = [Int16](repeating: 0, count: frames)
        var maxAmplitude: Float = 0

        for index in 0..<frames {
            let sample = monoSamples[index]
            let clamped = max(-1.0, min(1.0, Double(sample)))
            pcm16[index] = Int16(clamped * 32_767)
            maxAmplitude = max(maxAmplitude, abs(sample))
        }

        let data = pcm16.withUnsafeBytes { Data($0) }
        fileQueue.async { [weak self] in
            guard let self, self.isRecording else { return }

            do {
                try self.audioFileHandle?.write(contentsOf: data)
                try self.chunkFileHandle?.write(contentsOf: data)
                self.bytesWritten += Int64(data.count)
                self.chunkBytesWritten += Int64(data.count)
            } catch {
                return
            }

            if self.bytesWritten > self.maxFileSize {
                self.logger.log("Maximum file size reached (\(self.maxFileSize / (1024 * 1024)) MB) — stopping recording")
                self.onInterruption?(RecorderInterruptionEvent(type: .fileSizeLimit, reason: "Maximum file size reached"))
                self.stopRecording()
            }
        }

        let now = DispatchTime.now().uptimeNanoseconds
        if now - lastAmplitudeDispatchTime >= amplitudeMinIntervalNs {
            lastAmplitudeDispatchTime = now
            let scaledAmplitude = pow(Double(maxAmplitude), 0.3)
            DispatchQueue.main.async { [weak self] in
                self?.onAmplitude?(scaledAmplitude)
            }
        }
    }

    private func setupInterruptionHandling() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAudioInterruption(notification)
        }
    }

    private func setupLifecycleObserver() {
        guard !lifecycleObserverAdded else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        lifecycleObserverAdded = true
    }

    @objc private func handleAppWillTerminate() {
        teardownForAppTermination()
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let value = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: value)
        else {
            return
        }

        switch type {
        case .began:
            guard isRecording, !isManuallyPaused else { return }
            logger.log("Audio session interrupted — pausing recording")
            isPausedByInterruption = true
            inputNode?.removeTap(onBus: bus)
            engine?.stop()
            stopChunking()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            logger.log("Recording paused due to audio interruption ✓")
            onInterruption?(RecorderInterruptionEvent(type: .interruptionPause, reason: "Recording paused due to interruption"))
        case .ended:
            if isPausedByInterruption && !isManuallyPaused {
                logger.log("Audio interruption ended — auto-resuming recording")
                isResumingFromInterruption = true
                Task { @MainActor in
                    do {
                        _ = try await self.resumeRecording()
                    } catch {
                        isResumingFromInterruption = false
                        logger.log("Auto-resume failed — \(error.localizedDescription)")
                        onInterruption?(RecorderInterruptionEvent(type: .autoResumeFailed, reason: "Manual resume is required after interruption"))
                    }
                }
            } else {
                logger.log("Audio interruption ended")
            }
        @unknown default:
            break
        }
    }

    private func startChunking(rootURL: URL, seconds: Int) {
        stopChunking()
        try? FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        logger.log("Chunking started — interval: \(seconds)s, dir: \(rootURL.path)")
        rotateChunk(rootURL: rootURL)

        let timer = DispatchSource.makeTimerSource(queue: fileQueue)
        timer.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds))
        timer.setEventHandler { [weak self] in
            self?.rotateChunk(rootURL: rootURL)
        }
        timer.resume()
        chunkTimer = timer
    }

    private func stopChunking() {
        if let chunkTimer {
            chunkTimer.setEventHandler {}
            chunkTimer.cancel()
            self.chunkTimer = nil
        }

        fileQueue.sync {
            guard let handle = chunkFileHandle else { return }
            try? handle.synchronize()
            try? handle.close()
            if let chunkFileURL {
                if chunkBytesWritten > 0 {
                    logger.log("Final chunk saved: \(chunkFileURL.path) (\(chunkBytesWritten) bytes) — dispatching")
                    DispatchQueue.main.async { [weak self] in
                        self?.onChunkReady?(chunkFileURL)
                    }
                } else {
                    logger.log("Final chunk was empty — discarding: \(chunkFileURL.path)")
                    try? FileManager.default.removeItem(at: chunkFileURL)
                }
            }
            chunkFileHandle = nil
            chunkFileURL = nil
            chunkBytesWritten = 0
        }
    }

    private func rotateChunk(rootURL: URL) {
        if let handle = chunkFileHandle {
            try? handle.synchronize()
            try? handle.close()
            if let chunkFileURL {
                if chunkBytesWritten > 0 {
                    logger.log("Chunk saved: \(chunkFileURL.path) (\(chunkBytesWritten) bytes) — dispatching")
                    DispatchQueue.main.async { [weak self] in
                        self?.onChunkReady?(chunkFileURL)
                    }
                } else {
                    logger.log("Chunk was empty — discarding: \(chunkFileURL.path)")
                    try? FileManager.default.removeItem(at: chunkFileURL)
                }
            }
        }

        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let nextChunkURL = rootURL.appendingPathComponent("\(timestamp).pcm")
        FileManager.default.createFile(atPath: nextChunkURL.path, contents: nil)
        chunkFileHandle = try? FileHandle(forWritingTo: nextChunkURL)
        chunkFileURL = nextChunkURL
        chunkBytesWritten = 0
        logger.log("New chunk file opened: \(nextChunkURL.path)")
    }

    private func awaitResumeConfirmation(timeoutMs: Int = 1500) async throws -> Bool {
        cancelManualResumeConfirmationTimer()
        let timer = DispatchSource.makeTimerSource(queue: audioQueue)
        timer.schedule(deadline: .now() + .milliseconds(timeoutMs))
        timer.setEventHandler { [weak self] in
            guard let self, self.isResumeInProgress else { return }
            self.logger.log("Resume timed out — no audio buffers received within \(timeoutMs)ms")
            self.isResumeInProgress = false
            self.inputNode?.removeTap(onBus: self.bus)
            self.engine?.stop()
            self.stopChunking()
            self.resolveResumeWaiters(.failure(NativeAudioRecorderError.sessionSetupFailed("No audio buffers were received after resume.")))
        }
        timer.resume()
        manualResumeConfirmationTimer = timer

        return try await withCheckedThrowingContinuation { continuation in
            audioQueue.async { [weak self] in
                self?.resumeWaiters.append(continuation)
            }
        }
    }

    private func cancelManualResumeConfirmationTimer() {
        if let manualResumeConfirmationTimer {
            manualResumeConfirmationTimer.setEventHandler {}
            manualResumeConfirmationTimer.cancel()
            self.manualResumeConfirmationTimer = nil
        }
    }

    private func resolveResumeWaiters(_ result: Result<Bool, Error>) {
        let waiters = resumeWaiters
        resumeWaiters.removeAll()
        for waiter in waiters {
            switch result {
            case .success(let value):
                waiter.resume(returning: value)
            case .failure(let error):
                waiter.resume(throwing: error)
            }
        }
    }
}
