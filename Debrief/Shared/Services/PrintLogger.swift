import Foundation

final class PrintLogger: @unchecked Sendable {
    static let shared = PrintLogger()

    var enableLogs = true

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {}

    func log(_ message: String, file: String = #file, function: String = #function) {
        guard enableLogs else { return }
        let timestamp = formatter.string(from: Date())
        let filename = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        print("[\(timestamp)][\(filename)] \(message)")
    }
}
