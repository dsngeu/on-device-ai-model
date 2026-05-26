import Combine
import Foundation

@MainActor
final class RecordingViewModel: ObservableObject {
    @Published private(set) var stage: RecordingStage = .idle
    @Published private(set) var elapsedSeconds = 0
    @Published private(set) var amplitude: Double = 0
    @Published private(set) var liveTranscript = ""
    @Published private(set) var liveStatus: LiveTranscriptStatus = .idle
    @Published private(set) var chunksReceived = 0
    @Published private(set) var chunksTranscribed = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var interruptionMessage: String?

    let topic: String?

    private let store: AppStore
    private let onFinish: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(store: AppStore, initialTopic: String?, onFinish: @escaping () -> Void) {
        self.store = store
        self.topic = initialTopic
        self.onFinish = onFinish

        store.$recordingRuntime
            .sink { [weak self] runtime in
                guard let self else { return }
                self.stage = runtime.stage
                self.elapsedSeconds = runtime.durationSeconds
                self.amplitude = runtime.amplitude
                self.liveTranscript = runtime.liveTranscript
                self.liveStatus = runtime.liveStatus
                self.chunksReceived = runtime.chunksReceived
                self.chunksTranscribed = runtime.chunksTranscribed
                self.errorMessage = runtime.errorMessage
                self.interruptionMessage = runtime.interruptionMessage
            }
            .store(in: &cancellables)
    }

    func onAppear() {
        if store.recordingRuntime.recordingID == nil {
            Task { [weak self] in
                await self?.store.beginRecording(topic: self?.topic)
            }
        }
    }

    func onDisappear() {
    }

    func didTapPauseResume() {
        switch stage {
        case .recording:
            store.pauseActiveRecording()
        case .paused:
            store.resumeActiveRecording()
        default:
            break
        }
    }

    func didTapStop() {
        store.stopActiveRecording()
        onFinish()
    }

    func didTapDiscard() {
        store.discardActiveRecording()
        onFinish()
    }

    var elapsedText: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var statusText: String {
        switch stage {
        case .recording:
            return interruptionMessage ?? "Recording locally"
        case .paused:
            return interruptionMessage ?? "Paused"
        case .transcribing:
            return "Finishing live transcript"
        case .done:
            return "Saved"
        case .error:
            return "Error"
        case .idle:
            return "Preparing"
        }
    }
}
