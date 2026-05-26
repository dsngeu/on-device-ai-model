import Combine
import Foundation

enum MeetingSortOption: String, CaseIterable, Identifiable {
    case newest = "Newest"
    case oldest = "Oldest"
    case title = "A-Z"

    var id: String { rawValue }
}

@MainActor
final class MeetingsViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var sortOption: MeetingSortOption = .newest
    @Published private(set) var meetings: [Meeting] = []
    @Published private(set) var totalCount = 0

    private let store: AppStore
    private let onSelectMeeting: (String) -> Void
    private let onOpenQueue: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        store: AppStore,
        onSelectMeeting: @escaping (String) -> Void,
        onOpenQueue: @escaping () -> Void
    ) {
        self.store = store
        self.onSelectMeeting = onSelectMeeting
        self.onOpenQueue = onOpenQueue

        store.$meetings
            .map(\.count)
            .assign(to: &$totalCount)

        Publishers.CombineLatest3(store.$meetings, $searchText, $sortOption)
            .map { meetings, searchText, sortOption in
                Self.filterAndSort(meetings: meetings, searchText: searchText, sortOption: sortOption)
            }
            .assign(to: &$meetings)
    }

    func didSelectMeeting(_ meeting: Meeting) {
        onSelectMeeting(meeting.id)
    }

    func didTapRetry(_ meeting: Meeting) {
        store.retryMeeting(meeting.id)
        onOpenQueue()
    }

    private static func filterAndSort(
        meetings: [Meeting],
        searchText: String,
        sortOption: MeetingSortOption
    ) -> [Meeting] {
        let filtered = meetings.filter { meeting in
            guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return true
            }

            let haystack = [
                meeting.title,
                meeting.summary,
                meeting.transcript,
                meeting.topics.joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(searchText.lowercased())
        }

        switch sortOption {
        case .newest:
            return filtered.sorted { $0.recordedAt > $1.recordedAt }
        case .oldest:
            return filtered.sorted { $0.recordedAt < $1.recordedAt }
        case .title:
            return filtered.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
}
