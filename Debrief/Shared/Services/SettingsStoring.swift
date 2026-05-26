import Combine
import Foundation

@MainActor
protocol SettingsStoring: AnyObject {
    var availableSummaryModels: [SummaryModel] { get }
    var settings: AppSettings { get }
    var settingsPublisher: AnyPublisher<AppSettings, Never> { get }
    var downloadErrorMessage: String? { get }
    var downloadErrorMessagePublisher: AnyPublisher<String?, Never> { get }

    func selectSummaryModel(modelID: String)
    func downloadSummaryModel(modelID: String)
    func cancelSummaryModelDownload(modelID: String)
    func removeSummaryModel(modelID: String)
}

extension AppStore: SettingsStoring {
    var settingsPublisher: AnyPublisher<AppSettings, Never> {
        $settings.eraseToAnyPublisher()
    }

    var downloadErrorMessagePublisher: AnyPublisher<String?, Never> {
        $downloadErrorMessage.eraseToAnyPublisher()
    }
}
