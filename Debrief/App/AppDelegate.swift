import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundDownloadService.sessionIdentifier else {
            completionHandler()
            return
        }

        BackgroundDownloadService.shared.setBackgroundCompletionHandler(completionHandler)
    }
}
