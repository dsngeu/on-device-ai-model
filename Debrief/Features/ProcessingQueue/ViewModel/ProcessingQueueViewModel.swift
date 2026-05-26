import Combine
import Foundation

@MainActor
final class ProcessingQueueViewModel: ObservableObject {
    @Published private(set) var items: [QueueItem] = []
    @Published var itemPendingDeletion: QueueItem?

    private let store: AppStore
    private let onOpenMeeting: (String) -> Void
    private var cancellables = Set<AnyCancellable>()

    init(store: AppStore, onOpenMeeting: @escaping (String) -> Void) {
        self.store = store
        self.onOpenMeeting = onOpenMeeting

        store.$queueItems
            .map { $0.sorted(by: { $0.createdAt > $1.createdAt }) }
            .assign(to: &$items)
    }

    func didTapPrimaryAction(for item: QueueItem) {
        if item.state == .done, let meetingID = item.meetingID {
            onOpenMeeting(meetingID)
        } else {
            store.toggleQueueState(for: item.id)
        }
    }

    func didTapCancel(for item: QueueItem) {
        store.cancelQueueItem(item.id)
    }

    func didTapDelete(for item: QueueItem) {
        itemPendingDeletion = item
    }

    func confirmDelete() {
        guard let item = itemPendingDeletion else { return }
        store.deleteQueueItem(item.id)
        itemPendingDeletion = nil
    }

    func cancelDelete() {
        itemPendingDeletion = nil
    }
}
