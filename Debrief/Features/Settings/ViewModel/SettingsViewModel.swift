//feature/settings/viewmodel/settingsviewmodel.swift
import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var availableSummaryModels: [SummaryModel]
    @Published private(set) var settings: AppSettings
    @Published private(set) var downloadErrorMessage: String?

    private let store: any SettingsStoring
    private var cancellables = Set<AnyCancellable>()

    init(store: any SettingsStoring) {
        self.store = store
        self.availableSummaryModels = store.availableSummaryModels
        self.settings = store.settings

        store.settingsPublisher
            .assign(to: &$settings)

        store.downloadErrorMessagePublisher
            .assign(to: &$downloadErrorMessage)
    }

    func modelState(for modelID: String) -> ModelDownloadState {
        settings.summaryModelStates[modelID] ?? ModelDownloadState()
    }

    func didSelectSummaryModel(modelID: String) {
        store.selectSummaryModel(modelID: modelID)
    }

    func didTapSummaryModel(modelID: String) {
        let state = modelState(for: modelID)
        if state.status == .downloading {
            store.cancelSummaryModelDownload(modelID: modelID)
        } else if state.status == .downloaded || state.status == .active {
            store.removeSummaryModel(modelID: modelID)
        } else {
            store.downloadSummaryModel(modelID: modelID)
        }
    }
}
