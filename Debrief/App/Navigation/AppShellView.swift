import Combine
import SwiftUI

@MainActor
final class AppNavigator: ObservableObject {
    @Published var path: [AppRoute] = []

    func showRecording(topic: String?) {
        path.append(.recording(topic: topic))
    }

    func showProcessingQueue() {
        path.append(.processingQueue)
    }

    func showMeetingDetail(id: String) {
        path.append(.meetingDetail(id: id))
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }
}

struct AppShellView: View {
    @ObservedObject var store: AppStore
    @StateObject private var navigator = AppNavigator()
    @State private var selectedTab: AppTab = .home

    var body: some View {
        NavigationStack(path: $navigator.path) {
            TabView(selection: $selectedTab) {
                HomeView(
                    viewModel: HomeViewModel(
                        store: store,
                        onStartRecording: { navigator.showRecording(topic: $0) },
                        onOpenQueue: { navigator.showProcessingQueue() },
                        onOpenSettings: { selectedTab = .settings }
                    )
                )
                .tag(AppTab.home)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }

                MeetingsView(
                    viewModel: MeetingsViewModel(
                        store: store,
                        onSelectMeeting: { navigator.showMeetingDetail(id: $0) },
                        onOpenQueue: { navigator.showProcessingQueue() }
                    )
                )
                .tag(AppTab.meetings)
                .tabItem {
                    Label("Meetings", systemImage: "doc.text.fill")
                }

                SettingsView(
                    viewModel: SettingsViewModel(store: store)
                )
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .toolbarBackground(AppTheme.Colors.tabBar, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
            .background(AppTheme.Colors.background.ignoresSafeArea())
            .navigationDestination(for: AppRoute.self) { route in
                switch route {
                case .recording(let topic):
                    RecordingView(
                        viewModel: RecordingViewModel(
                            store: store,
                            initialTopic: topic,
                            onFinish: { navigator.popToRoot() }
                        )
                    )
                case .processingQueue:
                    ProcessingQueueView(
                        viewModel: ProcessingQueueViewModel(
                            store: store,
                            onOpenMeeting: { navigator.showMeetingDetail(id: $0) }
                        )
                    )
                case .meetingDetail(let id):
                    MeetingDetailView(
                        viewModel: MeetingDetailViewModel(
                            store: store,
                            meetingID: id,
                            onClose: { navigator.pop() },
                            onOpenQueue: { navigator.showProcessingQueue() }
                        )
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
