import Combine
import Foundation
import UIKit

struct CopyFeedback: Equatable {
    let message: String
}

@MainActor
final class MeetingDetailViewModel: ObservableObject {
    @Published private(set) var meeting: Meeting?
    @Published private(set) var exportText = ""
    @Published private(set) var exportMarkdown = ""
    @Published private(set) var copyFeedback: CopyFeedback?
    @Published var showAudioPlayer = false

    let playback = AudioPlaybackController()

    private let store: AppStore
    private let meetingID: String
    private let onClose: () -> Void
    private let onOpenQueue: () -> Void
    private let exporter = MeetingExportService()
    private var cancellables = Set<AnyCancellable>()
    private var copyFeedbackTask: Task<Void, Never>?

    var canCopyTranscript: Bool {
        guard let transcript = meeting?.transcript else { return false }
        return !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canCopyFullNote: Bool {
        !exportText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        store: AppStore,
        meetingID: String,
        onClose: @escaping () -> Void,
        onOpenQueue: @escaping () -> Void
    ) {
        self.store = store
        self.meetingID = meetingID
        self.onClose = onClose
        self.onOpenQueue = onOpenQueue

        store.$meetings
            .map { meetings in
                meetings.first(where: { $0.id == meetingID })
            }
            .handleEvents(receiveOutput: { [weak self] meeting in
                guard let self else { return }
                guard let meeting else {
                    self.exportText = ""
                    self.exportMarkdown = ""
                    return
                }

                self.exportText = exporter.plainText(for: meeting)
                self.exportMarkdown = exporter.markdown(for: meeting)
            })
            .assign(to: &$meeting)
    }

    func didTapDelete() {
        store.deleteMeeting(meetingID)
        onClose()
    }

    func didTapRetry() {
        store.retryMeeting(meetingID)
        onOpenQueue()
    }

    func didTapReSummarize() {
        store.reSummarizeMeeting(meetingID)
        onOpenQueue()
    }

    func didTapPlayPause() {
        guard meeting?.audioPath != nil else { return }
        showAudioPlayer = true
    }

    func didTapCopyTranscript() {
        guard let meeting else { return }
        let transcript = meeting.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { return }
        UIPasteboard.general.string = transcript
        showCopyFeedback(message: "Transcription copied")
    }

    func didTapCopyFullNote() {
        let fullNote = exportText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullNote.isEmpty else { return }
        UIPasteboard.general.string = fullNote
        showCopyFeedback(message: "Full note copied")
    }

    private func showCopyFeedback(message: String) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copyFeedbackTask?.cancel()
        copyFeedback = CopyFeedback(message: message)
        copyFeedbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            self?.copyFeedback = nil
        }
    }
}
