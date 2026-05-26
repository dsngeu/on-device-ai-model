import Combine
import Foundation

struct QueueSummary: Hashable {
    let queued: Int
    let processing: Int
    let paused: Int
    let failed: Int

    var total: Int {
        queued + processing + paused + failed
    }

    var detailText: String {
        var parts: [String] = []

        if processing > 0 {
            parts.append("\(processing) in progress")
        }

        if queued > 0 {
            parts.append("\(queued) queued")
        }

        if paused > 0 {
            parts.append("\(paused) paused")
        }

        if failed > 0 {
            parts.append("\(failed) failed")
        }

        return parts.joined(separator: " · ")
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var queueSummary = QueueSummary(queued: 0, processing: 0, paused: 0, failed: 0)
    @Published private(set) var hasDownloadedModel = false

    private let onStartRecording: (String?) -> Void
    private let onOpenQueue: () -> Void
    private let onOpenSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        store: AppStore,
        onStartRecording: @escaping (String?) -> Void,
        onOpenQueue: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onStartRecording = onStartRecording
        self.onOpenQueue = onOpenQueue
        self.onOpenSettings = onOpenSettings

        store.$queueItems
            .map { items in
                QueueSummary(
                    queued: items.filter { $0.state == .queued }.count,
                    processing: items.filter { $0.state == .transcribing || $0.state == .summarizing }.count,
                    paused: items.filter { $0.state == .paused }.count,
                    failed: items.filter { $0.state == .failed }.count
                )
            }
            .assign(to: &$queueSummary)

        store.$settings
            .map { settings in
                let state = settings.summaryModelStates[settings.selectedSummaryModelID] ?? ModelDownloadState()
                return state.status == .downloaded || state.status == .active
            }
            .assign(to: &$hasDownloadedModel)
    }

    func didTapRecord() {
        onStartRecording(nil)
    }

    func didTapQueue() {
        onOpenQueue()
    }

    func didTapSettingsBanner() {
        onOpenSettings()
    }
}
