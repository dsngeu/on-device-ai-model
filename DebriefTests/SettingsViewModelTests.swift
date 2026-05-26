import Combine
import Foundation
import Testing

@testable import Debrief

// MARK: - Mock

@MainActor
final class MockSettingsStore: SettingsStoring {
    let availableSummaryModels: [SummaryModel]

    @Published var settings: AppSettings
    @Published var downloadErrorMessage: String?

    var settingsPublisher: AnyPublisher<AppSettings, Never> { $settings.eraseToAnyPublisher() }
    var downloadErrorMessagePublisher: AnyPublisher<String?, Never> { $downloadErrorMessage.eraseToAnyPublisher() }

    private(set) var selectedModelID: String?
    private(set) var downloadedModelID: String?
    private(set) var cancelledModelID: String?
    private(set) var removedModelID: String?

    init(models: [SummaryModel] = [], settings: AppSettings = AppSettings()) {
        self.availableSummaryModels = models
        self.settings = settings
    }

    func selectSummaryModel(modelID: String) { selectedModelID = modelID }
    func downloadSummaryModel(modelID: String) { downloadedModelID = modelID }
    func cancelSummaryModelDownload(modelID: String) { cancelledModelID = modelID }
    func removeSummaryModel(modelID: String) { removedModelID = modelID }
}

// MARK: - Tests

@MainActor
@Suite("SettingsViewModel")
struct SettingsViewModelTests {
    private func makeModel(id: String = "model-1") -> SummaryModel {
        SummaryModel(
            id: id,
            name: "Test Model",
            size: "1 GB",
            sizeBytes: 1024 * 1024 * 1024,
            description: "A test model",
            downloadURL: URL(string: "https://example.com/model.gguf")!
        )
    }

    // 1. ViewModel reflects the store's available models on init.
    @Test func init_exposesAvailableModelsFromStore() {
        let models = [makeModel(id: "a"), makeModel(id: "b")]
        let store = MockSettingsStore(models: models)
        let sut = SettingsViewModel(store: store)

        #expect(sut.availableSummaryModels == models)
    }

    // 2. ViewModel reflects updated settings when the store publishes a new value.
    @Test func settings_updatesWhenStorePushesNewSettings() {
        let store = MockSettingsStore()
        let sut = SettingsViewModel(store: store)

        var updated = AppSettings()
        updated.selectedSummaryModelID = "new-model-id"
        store.settings = updated

        #expect(sut.settings.selectedSummaryModelID == "new-model-id")
    }

    // 3. Tapping a not-downloaded model starts a download.
    @Test func didTap_notDownloadedModel_startsDownload() {
        let model = makeModel()
        var settings = AppSettings()
        settings.summaryModelStates[model.id] = ModelDownloadState(status: .notDownloaded, progress: 0)
        let store = MockSettingsStore(models: [model], settings: settings)
        let sut = SettingsViewModel(store: store)

        sut.didTapSummaryModel(modelID: model.id)

        #expect(store.downloadedModelID == model.id)
        #expect(store.cancelledModelID == nil)
        #expect(store.removedModelID == nil)
    }

    // 4. Tapping a downloading model cancels the download.
    @Test func didTap_downloadingModel_cancelsDownload() {
        let model = makeModel()
        var settings = AppSettings()
        settings.summaryModelStates[model.id] = ModelDownloadState(status: .downloading, progress: 0.5)
        let store = MockSettingsStore(models: [model], settings: settings)
        let sut = SettingsViewModel(store: store)

        sut.didTapSummaryModel(modelID: model.id)

        #expect(store.cancelledModelID == model.id)
        #expect(store.downloadedModelID == nil)
        #expect(store.removedModelID == nil)
    }

    // 5. Selecting a model delegates to the store.
    @Test func didSelect_delegatesSelectionToStore() {
        let model = makeModel()
        let store = MockSettingsStore(models: [model])
        let sut = SettingsViewModel(store: store)

        sut.didSelectSummaryModel(modelID: model.id)

        #expect(store.selectedModelID == model.id)
    }
}
