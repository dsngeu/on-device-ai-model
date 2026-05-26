import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var recordings: [RecordingSession] = []
    @Published private(set) var queueItems: [QueueItem] = []
    @Published private(set) var settings: AppSettings
    @Published private(set) var queueStatus = ProcessingQueueStatus()
    @Published private(set) var recordingRuntime = RecordingRuntimeState()
    @Published private(set) var downloadErrorMessage: String?

    /// Available summary models. Order determines display order in settings.
    let availableSummaryModels: [SummaryModel]

    private let paths = DebriefPaths()
    private let audioConverter = AudioConversionService()
    private let transcriber = SpeechTranscriptionService()
    private let summarizer = SummaryService()
    private let llmSummarizer = LLMSummarizationService()
    private let recorder = NativeAudioRecorderService()
    private let logger = PrintLogger.shared
    private let downloadService = BackgroundDownloadService.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "debrief.app.settings.v1"

    private var currentSegmentID: String?
    private var queueTask: Task<Void, Never>?
    private var liveTranscriptionTask: Task<Void, Never>?
    private var pendingLiveChunks: [URL] = []
    private var recordingDurationTimer: Timer?
    private var recordingStartedAt: Date?
    private var accumulatedRecordingDuration: TimeInterval = 0
    private var isAppInBackground = false
    private var didEnterBackgroundObserver: NSObjectProtocol?
    private var willEnterForegroundObserver: NSObjectProtocol?

    init() {
        self.availableSummaryModels = [
            SummaryModel(
                id: "qwen2.5-1.5b-instruct",
                name: "Qwen 2.5 1.5B",
                size: "980 MB",
                sizeBytes: 980 * 1024 * 1024,
                description: "Generates local meeting summaries, decisions, and action items.",
                downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!
            ),
            SummaryModel(
                id: "phi-2-q4_k_m",
                name: "Phi-2",
                size: "1.8 GB",
                sizeBytes: Int64(1.8 * 1024 * 1024 * 1024),
                description: "Microsoft's 2.7B parameter model for summaries and action items.",
                downloadURL: URL(string: "https://huggingface.co/TheBloke/phi-2-GGUF/resolve/main/phi-2.Q4_K_M.gguf")!
            )
        ]

        self.settings = Self.loadSettings(defaults: userDefaults, key: settingsKey)
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        bindRecorderCallbacks()
        bindDownloadCallbacks()
        bindLifecycleCallbacks()
        bootstrap()
    }

    deinit {
        if let didEnterBackgroundObserver {
            NotificationCenter.default.removeObserver(didEnterBackgroundObserver)
        }
        if let willEnterForegroundObserver {
            NotificationCenter.default.removeObserver(willEnterForegroundObserver)
        }
    }

    func beginRecording(topic: String?) async {
        do {
            logger.log("beginRecording called — ID: \(String(Int(Date().timeIntervalSince1970 * 1000)))")
            print("beginRecording called — ID: \(String(Int(Date().timeIntervalSince1970 * 1000)))")
            try paths.ensureBaseDirectories()
            let granted = await recorder.requestPermission()
            guard granted else {
                logger.log("Microphone permission denied — cannot start recording")
                recordingRuntime = RecordingRuntimeState(stage: .error, errorMessage: NativeAudioRecorderError.permissionDenied.localizedDescription)
                return
            }

            let recordingID = String(Int(Date().timeIntervalSince1970 * 1000))
            let segmentID = recordingID
            currentSegmentID = segmentID
            let segmentURL = paths.segmentsDirectory(recordingID).appendingPathComponent("\(segmentID).pcm")
            let chunkRootURL = paths.chunksDirectory(recordingID, segmentID: segmentID)
            logger.log("Recording session created — ID: \(recordingID), segment: \(segmentURL.path)")

            let session = RecordingSession(
                id: recordingID,
                createdAt: .now,
                updatedAt: .now,
                meetingTopic: normalizedTitle(for: topic),
                participants: [],
                durationSeconds: 0,
                isRecordingComplete: false,
                isProcessing: false,
                queueState: nil,
                transcript: "",
                lastProcessedChunkTimestamp: nil,
                meetingID: nil,
                processingError: nil,
                audioRelativePath: paths.relativePath(for: segmentURL)
            )

            recordings.insert(session, at: 0)
            persistRecordings()
            refreshQueueItems()

            pendingLiveChunks = []
            recordingRuntime = RecordingRuntimeState(
                recordingID: recordingID,
                topic: session.meetingTopic,
                stage: .recording,
                durationSeconds: 0,
                amplitude: 0,
                liveTranscript: "",
                liveStatus: .waitingChunks,
                chunksReceived: 0,
                chunksTranscribed: 0,
                lastChunkAt: nil,
                errorMessage: nil
            )

            try recorder.startRecording(segmentURL: segmentURL, chunkRootURL: chunkRootURL, chunkSeconds: 5)
            beginRecordingDurationClock()
            logger.log("Recording pipeline active ✓ — ID: \(recordingID)")
        } catch {
            logger.log("beginRecording failed — \(error.localizedDescription)")
            recordingRuntime.stage = .error
            recordingRuntime.errorMessage = error.localizedDescription
        }
    }

    func pauseActiveRecording() {
        logger.log("Pausing active recording — ID: \(recordingRuntime.recordingID ?? "unknown")")
        do {
            try recorder.pauseRecording()
            recordingRuntime.stage = .paused
            pauseRecordingDurationClock()
            logger.log("Active recording paused ✓")
        } catch {
            logger.log("pauseActiveRecording failed — \(error.localizedDescription)")
            recordingRuntime.stage = .error
            recordingRuntime.errorMessage = error.localizedDescription
        }
    }

    func resumeActiveRecording() {
        logger.log("Resuming active recording — ID: \(recordingRuntime.recordingID ?? "unknown")")
        Task {
            do {
                _ = try await recorder.resumeRecording()
                recordingRuntime.stage = .recording
                resumeRecordingDurationClock()
                logger.log("Active recording resumed ✓")
            } catch {
                logger.log("resumeActiveRecording failed — \(error.localizedDescription)")
                recordingRuntime.stage = .error
                recordingRuntime.errorMessage = error.localizedDescription
            }
        }
    }

    func stopActiveRecording() {
        logger.log("Stopping active recording — ID: \(recordingRuntime.recordingID ?? "unknown"), duration: \(recordingRuntime.durationSeconds)s")
        pauseRecordingDurationClock()
        recorder.stopRecording()

        Task {
            logger.log("Waiting for live transcription to settle before finalizing...")
            await waitForLiveTranscriptionToSettle()
            logger.log("Live transcription settled — finalizing recording")
            finalizeActiveRecording(queueState: .queued)
            enqueueQueueProcessingIfNeeded()
        }
    }

    func discardActiveRecording() {
        logger.log("Discarding active recording — ID: \(recordingRuntime.recordingID ?? "unknown")")
        pauseRecordingDurationClock()
        recorder.stopRecording()

        guard let recordingID = recordingRuntime.recordingID else {
            logger.log("No active recording ID — resetting runtime")
            resetRecordingRuntime()
            return
        }

        deleteRecordingArtifacts(recordingID: recordingID)
        recordings.removeAll { $0.id == recordingID }
        persistRecordings()
        refreshQueueItems()
        resetRecordingRuntime()
        logger.log("Recording discarded and artifacts deleted — ID: \(recordingID)")
    }

    func retryMeeting(_ meetingID: String) {
        guard let recordingID = recordingID(forMeetingID: meetingID) else { return }
        retryRecording(recordingID)
    }

    /// Schedules the meeting's recording for re-summarization. Transcription is preserved; only summarization runs again.
    func reSummarizeMeeting(_ meetingID: String) {
        guard let recordingID = recordingID(forMeetingID: meetingID) else { return }
        logger.log("Re-summarize scheduled — meeting ID: \(meetingID), recording ID: \(recordingID)")
        retryRecording(recordingID)
    }

    func retryRecording(_ recordingID: String) {
        logger.log("Retrying recording — ID: \(recordingID)")
        let previousMeetingID = recordings.first(where: { $0.id == recordingID })?.meetingID

        updateRecording(id: recordingID) {
            $0.isProcessing = false
            $0.queueState = .queued
            $0.processingError = nil
            $0.meetingID = nil
            $0.updatedAt = .now
        }

        if let meetingID = previousMeetingID {
            meetings.removeAll { $0.id == meetingID }
            persistMeetings()
        }

        persistRecordings()
        refreshQueueItems()
        enqueueQueueProcessingIfNeeded()
        logger.log("Recording re-queued for retry ✓ — ID: \(recordingID)")
    }

    func deleteMeeting(_ meetingID: String) {
        logger.log("Deleting meeting — ID: \(meetingID)")
        if let recordingID = recordingID(forMeetingID: meetingID) {
            deleteRecordingArtifacts(recordingID: recordingID)
            recordings.removeAll { $0.id == recordingID }
            persistRecordings()
        }

        meetings.removeAll { $0.id == meetingID }
        persistMeetings()
        refreshQueueItems()
        logger.log("Meeting deleted ✓ — ID: \(meetingID)")
    }

    func toggleQueueState(for itemID: QueueItem.ID) {
        updateRecording(id: itemID) { recording in
            switch recording.queueState {
            case .paused:
                recording.queueState = .queued
            case .queued:
                recording.queueState = .paused
            case .failed:
                recording.queueState = .queued
                recording.processingError = nil
            case .none:
                break
            }
            recording.updatedAt = .now
        }
        persistRecordings()
        refreshQueueItems()
        enqueueQueueProcessingIfNeeded()
    }

    func cancelQueueItem(_ itemID: QueueItem.ID) {
        updateRecording(id: itemID) {
            $0.isProcessing = false
            $0.queueState = .paused
            $0.updatedAt = .now
        }
        persistRecordings()
        refreshQueueItems()
    }

    func deleteQueueItem(_ itemID: QueueItem.ID) {
        let meetingID = recordings.first(where: { $0.id == itemID })?.meetingID

        deleteRecordingArtifacts(recordingID: itemID)
        recordings.removeAll { $0.id == itemID }
        persistRecordings()

        if let meetingID {
            meetings.removeAll { $0.id == meetingID }
            persistMeetings()
        }

        refreshQueueItems()
    }

    func selectSummaryModel(modelID: String) {
        guard availableSummaryModels.contains(where: { $0.id == modelID }) else { return }
        settings.selectedSummaryModelID = modelID
        persistSettings()
    }

    func downloadSummaryModel(modelID: String) {
        guard let model = availableSummaryModels.first(where: { $0.id == modelID }) else { return }
        logger.log("Starting summary model download — ID: \(model.id), size: \(model.size)")
        downloadErrorMessage = nil
        setModelState(ModelDownloadState(status: .downloading, progress: 0), for: modelID)
        persistSettings()
        downloadService.start(
            BackgroundDownloadJob(
                id: model.id,
                sourceURL: model.downloadURL,
                destinationURL: paths.modelsRoot.appendingPathComponent("\(model.id).gguf"),
                requiresWiFi: false,
                isSummaryModel: true,
                markAsActiveOnCompletion: false
            )
        )
    }

    func cancelSummaryModelDownload(modelID: String) {
        downloadErrorMessage = nil
        setModelState(ModelDownloadState(status: .notDownloaded, progress: 0), for: modelID)
        try? FileManager.default.removeItem(at: paths.modelsRoot.appendingPathComponent("\(modelID).gguf"))
        persistSettings()
        Task {
            await downloadService.cancel(jobID: modelID)
        }
    }

    func removeSummaryModel(modelID: String) {
        try? FileManager.default.removeItem(at: paths.modelsRoot.appendingPathComponent("\(modelID).gguf"))
        setModelState(ModelDownloadState(status: .notDownloaded, progress: 0), for: modelID)
        persistSettings()
    }

    private func bootstrap() {
        logger.log("AppStore bootstrap starting")
        do {
            try paths.ensureBaseDirectories()
        } catch {}

        recordings = loadArray(from: paths.recordingsStateURL)
        meetings = loadArray(from: paths.meetingsStateURL)
        logger.log("State loaded — \(meetings.count) meeting(s), \(recordings.count) recording(s)")
        recoverPersistedState()
        reconcileModelFilesWithDisk()
        refreshQueueItems()
        enqueueQueueProcessingIfNeeded()
        Task {
            await downloadService.restoreInFlightTasks()
        }
        logger.log("AppStore bootstrap complete ✓")
    }

    private var selectedSummaryModel: SummaryModel {
        availableSummaryModels.first { $0.id == settings.selectedSummaryModelID }
            ?? availableSummaryModels[0]
    }

    private func modelState(for modelID: String) -> ModelDownloadState {
        settings.summaryModelStates[modelID] ?? ModelDownloadState()
    }

    private func setModelState(_ state: ModelDownloadState, for modelID: String) {
        settings.summaryModelStates[modelID] = state
    }

    private func bindRecorderCallbacks() {
        recorder.onAmplitude = { [weak self] amplitude in
            Task { @MainActor in
                self?.recordingRuntime.amplitude = amplitude
            }
        }

        recorder.onChunkReady = { [weak self] chunkURL in
            Task { @MainActor in
                guard let self else { return }
                self.pendingLiveChunks.append(chunkURL)
                self.recordingRuntime.lastChunkAt = .now
                self.recordingRuntime.chunksReceived += 1
                self.logger.log("Chunk received: \(chunkURL.path) — total received: \(self.recordingRuntime.chunksReceived)")
                if self.recordingRuntime.liveStatus == .idle {
                    self.recordingRuntime.liveStatus = .waitingChunks
                }
                self.processLiveChunksIfNeeded()
            }
        }

        recorder.onInterruption = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event.type {
                case .manualPause:
                    self.pauseRecordingDurationClock()
                    self.recordingRuntime.stage = .paused
                    self.recordingRuntime.interruptionMessage = nil
                case .interruptionPause:
                    self.pauseRecordingDurationClock()
                    self.recordingRuntime.stage = .paused
                    self.recordingRuntime.interruptionMessage = event.reason
                    self.recordingRuntime.errorMessage = nil
                case .manualResume, .interruptionResume:
                    self.recordingRuntime.stage = .recording
                    self.resumeRecordingDurationClock()
                    self.recordingRuntime.errorMessage = nil
                    if event.type == .interruptionResume {
                        self.recordingRuntime.interruptionMessage = event.reason
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(3))
                            if self.recordingRuntime.interruptionMessage == "Recording resumed" {
                                self.recordingRuntime.interruptionMessage = nil
                            }
                        }
                    } else {
                        self.recordingRuntime.interruptionMessage = nil
                    }
                case .autoResumeFailed:
                    self.pauseRecordingDurationClock()
                    self.recordingRuntime.stage = .paused
                    self.recordingRuntime.errorMessage = event.reason
                    self.recordingRuntime.interruptionMessage = nil
                case .fileSizeLimit:
                    self.pauseRecordingDurationClock()
                    self.finalizeActiveRecording(queueState: .queued)
                    self.enqueueQueueProcessingIfNeeded()
                case .appTerminate:
                    self.pauseRecordingDurationClock()
                    self.finalizeActiveRecording(queueState: .queued)
                }
            }
        }
    }

    private func bindLifecycleCallbacks() {
        didEnterBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAppInBackground = true
                self.syncRecordingDurationFromClock()
                self.stopRecordingDurationTimer()
            }
        }

        willEnterForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAppInBackground = false
                self.syncRecordingDurationFromClock()
                if self.recordingRuntime.stage == .recording {
                    self.startRecordingDurationTimer()
                }
                self.processLiveChunksIfNeeded()
            }
        }
    }

    private func bindDownloadCallbacks() {
        downloadService.onProgress = { [weak self] jobID, progress in
            guard let self else { return }
            if self.availableSummaryModels.contains(where: { $0.id == jobID }) {
                self.setModelState(ModelDownloadState(status: .downloading, progress: progress), for: jobID)
            }
            let pct = Int(progress * 100)
            if pct % 10 == 0 {
                self.logger.log("Model download progress — ID: \(jobID), \(pct)%")
            }
            self.persistSettings()
        }

        downloadService.onCompletion = { [weak self] jobID, result in
            guard let self else { return }
            guard let model = self.availableSummaryModels.first(where: { $0.id == jobID }) else { return }

            switch result {
            case .success(let job):
                if job.isSummaryModel {
                    let size = self.fileSize(at: job.destinationURL)
                    let minSize = Int64(Double(model.sizeBytes) * 0.9)
                    if size < minSize {
                        self.logger.log("Summary model download appears incomplete — size: \(size / (1024 * 1024)) MB — removing")
                        try? FileManager.default.removeItem(at: job.destinationURL)
                        self.setModelState(ModelDownloadState(), for: jobID)
                        self.downloadErrorMessage = "Downloaded summary model looks incomplete. Please try again."
                    } else {
                        self.logger.log("Summary model downloaded ✓ — ID: \(jobID), size: \(size / (1024 * 1024)) MB")
                        self.setModelState(ModelDownloadState(status: .downloaded, progress: 1), for: jobID)
                        self.downloadErrorMessage = nil
                    }
                }
            case .failure(let error):
                self.setModelState(ModelDownloadState(), for: jobID)

                if error is CancellationError {
                    self.logger.log("Model download cancelled — ID: \(jobID)")
                    self.downloadErrorMessage = nil
                } else {
                    self.logger.log("Model download failed — ID: \(jobID), error: \(error.localizedDescription)")
                    self.downloadErrorMessage = error.localizedDescription
                }
            }

            self.persistSettings()
        }
    }

    private func processLiveChunksIfNeeded() {
        guard !isAppInBackground else { return }
        guard liveTranscriptionTask == nil else { return }
        logger.log("Live transcription task starting — \(pendingLiveChunks.count) chunk(s) pending")

        liveTranscriptionTask = Task { [weak self] in
            guard let self else { return }

            while true {
                let nextChunk: URL? = await MainActor.run {
                    guard !self.isAppInBackground else {
                        self.recordingRuntime.liveStatus = .waitingChunks
                        return nil
                    }
                    guard !self.pendingLiveChunks.isEmpty else { return nil }
                    self.recordingRuntime.liveStatus = .transcribing
                    return self.pendingLiveChunks.removeFirst()
                }

                guard let nextChunk else { break }

                await transcribeLiveChunk(nextChunk)

                await MainActor.run {
                    if self.pendingLiveChunks.isEmpty {
                        self.recordingRuntime.liveStatus = .waitingChunks
                    }
                }
            }

            await MainActor.run {
                self.liveTranscriptionTask = nil
                if self.recordingRuntime.stage == .done || self.recordingRuntime.stage == .idle {
                    self.recordingRuntime.liveStatus = .idle
                }
            }
        }
    }

    private func transcribeLiveChunk(_ chunkURL: URL) async {
        guard let recordingID = recordingRuntime.recordingID else { return }
        let timestamp = Int64(chunkURL.deletingPathExtension().lastPathComponent) ?? Int64(Date().timeIntervalSince1970 * 1000)
        let wavURL = paths.tmpLiveWavDirectory(recordingID).appendingPathComponent("\(timestamp).wav")

        logger.log("Live chunk transcription starting — \(chunkURL.path)")
        do {
            try FileManager.default.createDirectory(at: wavURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try audioConverter.convertPCMToWAV(inputURL: chunkURL, outputURL: wavURL)
            let text = try await transcriber.transcribe(audioURL: wavURL)

            if !text.isEmpty {
                updateRecording(id: recordingID) {
                    $0.transcript = $0.transcript.isEmpty ? text : $0.transcript + "\n" + text
                    $0.lastProcessedChunkTimestamp = timestamp
                    $0.updatedAt = .now
                }
                persistRecordings()

                if let updated = recordings.first(where: { $0.id == recordingID }) {
                    recordingRuntime.liveTranscript = updated.transcript
                    recordingRuntime.chunksTranscribed += 1
                    logger.log("Live chunk transcribed ✓ — chunk \(recordingRuntime.chunksTranscribed)/\(recordingRuntime.chunksReceived), \(text.count) chars")
                }
            } else {
                logger.log("Live chunk produced no text — \(chunkURL.path)")
            }
            try? FileManager.default.removeItem(at: wavURL)
        } catch {
            if shouldIgnoreChunkTranscriptionError(error) {
                logger.log("Live chunk transcription produced no speech — \(chunkURL.path)")
                recordingRuntime.liveStatus = .waitingChunks
            } else {
                logger.log("Live chunk transcription failed — \(chunkURL.path): \(error.localizedDescription)")
                recordingRuntime.liveStatus = .unavailable
            }
        }
    }

    private func waitForLiveTranscriptionToSettle() async {
        while liveTranscriptionTask != nil || !pendingLiveChunks.isEmpty {
            try? await Task.sleep(for: .milliseconds(150))
        }
    }

    private func finalizeActiveRecording(queueState: RecordingQueueState) {
        guard let recordingID = recordingRuntime.recordingID else { return }
        logger.log("Finalizing recording — ID: \(recordingID), duration: \(recordingRuntime.durationSeconds)s, queueState: \(queueState)")
        updateRecording(id: recordingID) {
            $0.durationSeconds = recordingRuntime.durationSeconds
            $0.isRecordingComplete = true
            $0.queueState = queueState
            $0.isProcessing = false
            $0.updatedAt = .now
        }
        persistRecordings()
        refreshQueueItems()
        resetRecordingRuntime()
        logger.log("Recording finalized ✓ — ID: \(recordingID)")
    }

    private func resetRecordingRuntime() {
        recordingRuntime = RecordingRuntimeState()
        currentSegmentID = nil
        resetRecordingDurationClock()
    }

    private func enqueueQueueProcessingIfNeeded() {
        guard queueTask == nil else { return }
        guard recordingRuntime.stage != .recording && recordingRuntime.stage != .paused else { return }
        guard recordings.contains(where: isQueuedRecording) else { return }
        logger.log("Queue processing task enqueued")

        queueTask = Task { [weak self] in
            guard let self else { return }
            while true {
                let nextRecordingID = await MainActor.run {
                    self.recordings
                        .filter(self.isQueuedRecording)
                        .sorted { $0.updatedAt < $1.updatedAt }
                        .first?
                        .id
                }

                guard let nextRecordingID else { break }
                await processQueuedRecording(recordingID: nextRecordingID)
            }

            await MainActor.run {
                self.queueStatus = ProcessingQueueStatus()
                self.queueTask = nil
                self.refreshQueueItems()
                self.logger.log("Queue processing task finished — all queued recordings processed")
            }
        }
    }

    private func processQueuedRecording(recordingID: String) async {
        guard let recording = recordings.first(where: { $0.id == recordingID }) else { return }
        logger.log("File processing started — ID: \(recordingID), topic: \(recording.meetingTopic ?? "(none)")")
        updateRecording(id: recordingID) {
            $0.isProcessing = true
            $0.processingError = nil
            $0.updatedAt = .now
        }
        queueStatus = ProcessingQueueStatus(activeRecordingID: recordingID, progress: 0, phase: .transcribing)
        refreshQueueItems()
        persistRecordings()

        do {
            let chunkFiles = try listChunkFiles(for: recordingID)
            var transcript = recordings.first(where: { $0.id == recordingID })?.transcript ?? ""
            var lastProcessed = recordings.first(where: { $0.id == recordingID })?.lastProcessedChunkTimestamp ?? 0

            logger.log("Chunk files found: \(chunkFiles.count) — existing transcript length: \(transcript.count) chars")

            if chunkFiles.isEmpty && transcript.isEmpty {
                throw NSError(domain: "DebriefQueue", code: 404, userInfo: [NSLocalizedDescriptionKey: "No chunks were available to process."])
            }

            let totalChunks = max(chunkFiles.count, 1)
            logger.log("Transcription started — \(chunkFiles.count) chunk(s) to process for recording ID: \(recordingID)")
            for (index, chunkFile) in chunkFiles.enumerated() {
                if recordingRuntime.stage == .recording || recordingRuntime.stage == .paused {
                    logger.log("Queue interrupted — recording became active while processing ID: \(recordingID)")
                    throw NSError(domain: "DebriefQueue", code: 499, userInfo: [NSLocalizedDescriptionKey: "Recording became active while queue processing was running."])
                }

                let timestamp = Int64(chunkFile.deletingPathExtension().lastPathComponent) ?? 0
                guard timestamp > lastProcessed else {
                    logger.log("Chunk already processed — skipping: \(chunkFile.path)")
                    continue
                }

                logger.log("Transcribing chunk \(index + 1)/\(totalChunks) — \(chunkFile.path)")
                let wavURL = paths.tmpWavDirectory(recordingID).appendingPathComponent("\(timestamp).wav")
                try FileManager.default.createDirectory(at: wavURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try audioConverter.convertPCMToWAV(inputURL: chunkFile, outputURL: wavURL)
                defer {
                    try? FileManager.default.removeItem(at: wavURL)
                }

                do {
                    let chunkTranscript = try await transcriber.transcribe(audioURL: wavURL)
                    if !chunkTranscript.isEmpty {
                        transcript = transcript.isEmpty ? chunkTranscript : transcript + "\n" + chunkTranscript
                        logger.log("Chunk \(index + 1)/\(totalChunks) transcribed ✓ — \(chunkTranscript.count) chars added, total: \(transcript.count) chars")
                    } else {
                        logger.log("Chunk \(index + 1)/\(totalChunks) produced no text — \(chunkFile.path)")
                    }
                } catch {
                    guard shouldIgnoreChunkTranscriptionError(error) else {
                        logger.log("Chunk \(index + 1)/\(totalChunks) transcription error (non-ignorable) — \(error.localizedDescription)")
                        throw error
                    }
                    logger.log("Chunk \(index + 1)/\(totalChunks) transcription error (ignored) — \(error.localizedDescription)")
                }

                lastProcessed = max(lastProcessed, timestamp)
                updateRecording(id: recordingID) {
                    $0.transcript = transcript
                    $0.lastProcessedChunkTimestamp = lastProcessed
                    $0.updatedAt = .now
                }
                persistRecordings()

                queueStatus.progress = Double(index + 1) / Double(totalChunks)
                refreshQueueItems()
            }

            logger.log("All chunks transcribed — total transcript: \(transcript.count) chars")

            if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.log("Transcript is empty — no speech detected in recording ID: \(recordingID)")
                throw NSError(
                    domain: "DebriefQueue",
                    code: 422,
                    userInfo: [NSLocalizedDescriptionKey: "No speech was detected in the recording, so Debrief could not generate notes."]
                )
            }

            queueStatus.phase = .summarizing
            logger.log("Final note generation started — recording ID: \(recordingID)")
            let latest = recordings.first(where: { $0.id == recordingID }) ?? recording
            let meetingTopic = latest.meetingTopic
            let meetingParticipants = latest.participants

            let summary: MeetingSummary
            let model = selectedSummaryModel
            let modelURL = paths.modelsRoot.appendingPathComponent("\(model.id).gguf")
            let state = modelState(for: model.id)
            if state.status == .downloaded || state.status == .active,
               FileManager.default.fileExists(atPath: modelURL.path) {
                logger.log("Using \(model.name) for summarization — recording ID: \(recordingID)")
                summary = await llmSummarizer.summarize(
                    transcript: transcript,
                    topic: meetingTopic,
                    participants: meetingParticipants,
                    modelURL: modelURL
                )
            } else {
                logger.log("Summary model not downloaded — using heuristic summarization")
                summary = await Task.detached { [summarizer] in
                    summarizer.summarize(transcript: transcript, topic: meetingTopic, participants: meetingParticipants)
                }.value
            }
            let meetingID = "m-\(recordingID)"
            logger.log("Summary generated — title: \"\(summary.title)\", actionItems: \(summary.actionItems.count), decisions: \(summary.keyDecisions.count), topics: \(summary.topics.count)")

            let meeting = Meeting(
                id: meetingID,
                title: summary.title,
                summary: summary.summary,
                summaryLines: summary.summaryLines,
                actionItems: summary.actionItems.enumerated().map { index, item in
                    ActionItem(id: "\(meetingID)-\(index)", person: item.person, task: item.task, dueDate: item.dueDate, completed: false)
                },
                keyDecisions: summary.keyDecisions,
                openQuestions: summary.openQuestions,
                topics: summary.topics,
                transcript: transcript,
                meetingTopic: latest.meetingTopic,
                participants: latest.participants,
                duration: latest.durationSeconds,
                recordedAt: latest.createdAt,
                modelUsed: model.id,
                audioPath: latest.audioRelativePath,
                status: .ready,
                processingError: nil
            )

            meetings.removeAll { $0.id == meetingID }
            meetings.insert(meeting, at: 0)
            persistMeetings()

            updateRecording(id: recordingID) {
                $0.meetingID = meetingID
                $0.isProcessing = false
                $0.queueState = nil
                $0.processingError = nil
                $0.updatedAt = .now
            }
            persistRecordings()
            cleanupQueueArtifacts(recordingID: recordingID)
            logger.log("Final note completed ✓ — meeting ID: \(meetingID), title: \"\(meeting.title)\"")
        } catch {
            logger.log("Queue processing failed — ID: \(recordingID), error: \(error.localizedDescription)")
            updateRecording(id: recordingID) {
                $0.isProcessing = false
                $0.queueState = .failed
                $0.processingError = error.localizedDescription
                $0.updatedAt = .now
            }
            persistRecordings()
        }

        refreshQueueItems()
    }

    private func shouldIgnoreChunkTranscriptionError(_ error: Error) -> Bool {
        if case TranscriptionServiceError.noTranscript = error {
            return true
        }

        let nsError = error as NSError
        let message = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        if message.contains("no speech")
            || message.contains("no speech detected")
            || message.contains("speech not detected") {
            return true
        }

        return false
    }

    private func isQueuedRecording(_ recording: RecordingSession) -> Bool {
        recording.isRecordingComplete && recording.meetingID == nil && recording.queueState == .queued && !recording.isProcessing
    }

    private func listChunkFiles(for recordingID: String) throws -> [URL] {
        let chunksRoot = paths.recordingDirectory(recordingID).appendingPathComponent("chunks", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(at: chunksRoot, includingPropertiesForKeys: nil) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "pcm" }
            .sorted { lhs, rhs in lhs.lastPathComponent < rhs.lastPathComponent }
    }

    private func cleanupQueueArtifacts(recordingID: String) {
        try? FileManager.default.removeItem(at: paths.recordingDirectory(recordingID).appendingPathComponent("chunks", isDirectory: true))
        try? FileManager.default.removeItem(at: paths.recordingDirectory(recordingID).appendingPathComponent("tmp", isDirectory: true))
    }

    private func deleteRecordingArtifacts(recordingID: String) {
        try? FileManager.default.removeItem(at: paths.recordingDirectory(recordingID))
    }

    private func recordingID(forMeetingID meetingID: String) -> String? {
        recordings.first(where: { $0.meetingID == meetingID })?.id ?? meetingID.replacingOccurrences(of: "m-", with: "")
    }

    private func refreshQueueItems() {
        queueItems = recordings.compactMap { recording in
            guard recording.isRecordingComplete else { return nil }
            guard recording.meetingID == nil || recording.isProcessing || recording.queueState != nil else { return nil }

            let state: QueueItemState = if queueStatus.activeRecordingID == recording.id {
                queueStatus.phase == .summarizing ? .summarizing : .transcribing
            } else if recording.isProcessing {
                .transcribing
            } else if recording.queueState == .paused {
                .paused
            } else if recording.queueState == .failed {
                .failed
            } else if recording.meetingID != nil {
                .done
            } else {
                .queued
            }

            return QueueItem(
                id: recording.id,
                meetingID: recording.meetingID,
                title: recording.meetingTopic ?? "Untitled recording",
                state: state,
                progress: queueStatus.activeRecordingID == recording.id ? queueStatus.progress : (state == .done ? 1 : 0),
                subtitle: queueSubtitle(for: recording, state: state),
                createdAt: recording.createdAt
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func queueSubtitle(for recording: RecordingSession, state: QueueItemState) -> String {
        switch state {
        case .queued:
            return "Ready for local transcription and summarization."
        case .transcribing:
            return "Converting chunk audio into transcript text."
        case .summarizing:
            return "Building summary, action items, and topics."
        case .paused:
            return "Paused by the user."
        case .failed:
            return recording.processingError ?? "Processing failed."
        case .done:
            return "Notes are ready to review."
        }
    }

    private func recoverPersistedState() {
        let stuckMeetings = meetings.filter { $0.status == .processing }.count
        let stuckRecordings = recordings.filter { $0.isProcessing && $0.meetingID == nil }.count
        if stuckMeetings > 0 || stuckRecordings > 0 {
            logger.log("Recovering persisted state — \(stuckMeetings) stuck meeting(s), \(stuckRecordings) stuck recording(s)")
        }

        for index in meetings.indices where meetings[index].status == .processing {
            meetings[index].status = .failed
            meetings[index].processingError = "Recovered after app restart while processing."
        }
        persistMeetings()

        for index in recordings.indices where recordings[index].isProcessing && recordings[index].meetingID == nil {
            recordings[index].isProcessing = false
            recordings[index].queueState = .queued
            recordings[index].updatedAt = .now
        }
        persistRecordings()

        if stuckMeetings > 0 || stuckRecordings > 0 {
            logger.log("Persisted state recovery complete ✓")
        }
    }

    private func reconcileModelFilesWithDisk() {
        let activeDownloadIDs = Set(downloadService.activeJobs().map(\.id))
        for model in availableSummaryModels {
            let modelURL = paths.modelsRoot.appendingPathComponent("\(model.id).gguf")
            if activeDownloadIDs.contains(model.id) {
                let current = modelState(for: model.id)
                setModelState(ModelDownloadState(status: .downloading, progress: current.progress), for: model.id)
            } else {
                let status: ModelStatus = FileManager.default.fileExists(atPath: modelURL.path)
                    ? .downloaded
                    : .notDownloaded
                setModelState(ModelDownloadState(status: status, progress: status == .downloaded ? 1 : 0), for: model.id)
            }
        }
        persistSettings()
    }

    private func loadArray<T: Decodable>(from url: URL) -> [T] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([T].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persistRecordings() {
        persist(recordings, to: paths.recordingsStateURL)
    }

    private func persistMeetings() {
        persist(meetings, to: paths.meetingsStateURL)
    }

    private func persistSettings() {
        if let data = try? encoder.encode(settings) {
            userDefaults.set(data, forKey: settingsKey)
        }
    }

    private func persist<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func loadSettings(defaults: UserDefaults, key: String) -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return AppSettings()
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    private func updateRecording(id: String, transform: (inout RecordingSession) -> Void) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        transform(&recordings[index])
    }

    private func normalizedTitle(for topic: String?) -> String? {
        let trimmed = topic?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return 0
        }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func startRecordingDurationTimer() {
        stopRecordingDurationTimer()
        recordingDurationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncRecordingDurationFromClock()
            }
        }
    }

    private func stopRecordingDurationTimer() {
        recordingDurationTimer?.invalidate()
        recordingDurationTimer = nil
    }

    private func beginRecordingDurationClock() {
        accumulatedRecordingDuration = 0
        recordingStartedAt = Date()
        recordingRuntime.durationSeconds = 0
        if !isAppInBackground {
            startRecordingDurationTimer()
        }
    }

    private func resumeRecordingDurationClock() {
        if recordingStartedAt == nil {
            recordingStartedAt = Date()
        }
        syncRecordingDurationFromClock()
        if !isAppInBackground {
            startRecordingDurationTimer()
        }
    }

    private func pauseRecordingDurationClock() {
        if let recordingStartedAt {
            accumulatedRecordingDuration += Date().timeIntervalSince(recordingStartedAt)
            self.recordingStartedAt = nil
        }
        syncRecordingDurationFromClock()
        stopRecordingDurationTimer()
    }

    private func resetRecordingDurationClock() {
        recordingStartedAt = nil
        accumulatedRecordingDuration = 0
        stopRecordingDurationTimer()
    }

    private func syncRecordingDurationFromClock() {
        recordingRuntime.durationSeconds = currentRecordingDurationSeconds()
    }

    private func currentRecordingDurationSeconds() -> Int {
        var totalDuration = accumulatedRecordingDuration
        if let recordingStartedAt {
            totalDuration += Date().timeIntervalSince(recordingStartedAt)
        }
        return max(0, Int(totalDuration.rounded(.down)))
    }
}
