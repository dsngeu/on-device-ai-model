import Foundation

struct BackgroundDownloadJob: Codable, Hashable {
    let id: String
    let sourceURL: URL
    let destinationURL: URL
    let requiresWiFi: Bool
    let isSummaryModel: Bool
    let markAsActiveOnCompletion: Bool
}

enum BackgroundDownloadError: LocalizedError {
    case missingJobMetadata
    case invalidResponse(statusCode: Int)
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .missingJobMetadata:
            return "Download metadata could not be restored."
        case .invalidResponse(let statusCode):
            return "Download failed with status code \(statusCode)."
        case .emptyFile:
            return "Downloaded file was empty."
        }
    }
}

final class BackgroundDownloadService: NSObject {
    typealias ProgressHandler = @MainActor (String, Double) -> Void
    typealias CompletionHandler = @MainActor (String, Result<BackgroundDownloadJob, Error>) -> Void

    static let shared = BackgroundDownloadService()
    static let sessionIdentifier = "com.debriefus.app.background-downloads"

    var onProgress: ProgressHandler?
    var onCompletion: CompletionHandler?

    private let jobsKey = "debrief.background-download-jobs"
    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private var backgroundCompletionHandler: (() -> Void)?
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let logger = PrintLogger.shared

    private override init() {
        super.init()
    }

    func setBackgroundCompletionHandler(_ completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }

    func activeJobs() -> [BackgroundDownloadJob] {
        Array(loadJobs().values)
    }

    func start(_ job: BackgroundDownloadJob) {
        logger.log("Background download starting — ID: \(job.id), url: \(job.sourceURL.lastPathComponent), wifiOnly: \(job.requiresWiFi)")
        Task {
            await cancel(jobID: job.id)

            var jobs = loadJobs()
            jobs[job.id] = job
            saveJobs(jobs)

            var request = URLRequest(url: job.sourceURL)
            request.allowsCellularAccess = !job.requiresWiFi
            if #available(iOS 13.0, *) {
                request.allowsExpensiveNetworkAccess = !job.requiresWiFi
                request.allowsConstrainedNetworkAccess = !job.requiresWiFi
            }

            let task = session.downloadTask(with: request)
            task.taskDescription = job.id
            task.earliestBeginDate = nil
            task.resume()
            logger.log("Background download task resumed ✓ — ID: \(job.id)")
        }
    }

    func cancel(jobID: String) async {
        logger.log("Cancelling background download — ID: \(jobID)")
        let tasks = await currentTasks()
        tasks
            .filter { $0.taskDescription == jobID }
            .forEach { $0.cancel() }

        var jobs = loadJobs()
        jobs.removeValue(forKey: jobID)
        saveJobs(jobs)
        logger.log("Background download cancelled ✓ — ID: \(jobID)")
    }

    func restoreInFlightTasks() async {
        let jobs = loadJobs()
        logger.log("Restoring in-flight downloads — persisted jobs: \(jobs.count)")
        let tasks = await currentTasks()
        let activeTaskIDs = Set(tasks.compactMap(\.taskDescription))

        for job in jobs.values where !activeTaskIDs.contains(job.id) {
            logger.log("In-flight job not found in active tasks — treating as cancelled: \(job.id)")
            var updatedJobs = loadJobs()
            updatedJobs.removeValue(forKey: job.id)
            saveJobs(updatedJobs)
            await MainActor.run { [weak self] in
                self?.onCompletion?(job.id, .failure(CancellationError()))
            }
        }
        logger.log("In-flight downloads restoration complete ✓ — active tasks: \(activeTaskIDs.count)")
    }

    private func currentTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    private func loadJobs() -> [String: BackgroundDownloadJob] {
        guard let data = defaults.data(forKey: jobsKey),
              let jobs = try? JSONDecoder().decode([String: BackgroundDownloadJob].self, from: data) else {
            return [:]
        }
        return jobs
    }

    private func saveJobs(_ jobs: [String: BackgroundDownloadJob]) {
        if jobs.isEmpty {
            defaults.removeObject(forKey: jobsKey)
            return
        }

        if let data = try? JSONEncoder().encode(jobs) {
            defaults.set(data, forKey: jobsKey)
        }
    }

    private func job(for task: URLSessionTask) -> BackgroundDownloadJob? {
        guard let id = task.taskDescription else { return nil }
        return loadJobs()[id]
    }

    private func finishBackgroundEventsIfNeeded() {
        guard let backgroundCompletionHandler else { return }
        self.backgroundCompletionHandler = nil
        DispatchQueue.main.async {
            backgroundCompletionHandler()
        }
    }
}

extension BackgroundDownloadService: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let jobID = downloadTask.taskDescription else { return }
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0

        Task { @MainActor [weak self] in
            self?.onProgress?(jobID, progress)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let job = job(for: downloadTask) else {
            logger.log("Download finished but job metadata missing — ID: \(downloadTask.taskDescription ?? "unknown")")
            Task { @MainActor [weak self] in
                self?.onCompletion?(downloadTask.taskDescription ?? "", .failure(BackgroundDownloadError.missingJobMetadata))
            }
            return
        }

        logger.log("Download finished — ID: \(job.id), moving to destination")
        do {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                logger.log("Download failed — HTTP \(response.statusCode) for ID: \(job.id)")
                throw BackgroundDownloadError.invalidResponse(statusCode: response.statusCode)
            }

            try fileManager.createDirectory(at: job.destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: job.destinationURL.path) {
                try fileManager.removeItem(at: job.destinationURL)
            }
            try fileManager.moveItem(at: location, to: job.destinationURL)

            let fileSize = (try fileManager.attributesOfItem(atPath: job.destinationURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            guard fileSize > 0 else {
                logger.log("Downloaded file is empty — ID: \(job.id)")
                throw BackgroundDownloadError.emptyFile
            }

            logger.log("Download complete — ID: \(job.id), size: \(fileSize / (1024 * 1024)) MB, dest: \(job.destinationURL.path)")
            var jobs = loadJobs()
            jobs.removeValue(forKey: job.id)
            saveJobs(jobs)

            Task { @MainActor [weak self] in
                self?.onCompletion?(job.id, .success(job))
            }
        } catch {
            logger.log("Download post-processing failed — ID: \(job.id), error: \(error.localizedDescription)")
            try? fileManager.removeItem(at: job.destinationURL)
            var jobs = loadJobs()
            jobs.removeValue(forKey: job.id)
            saveJobs(jobs)

            Task { @MainActor [weak self] in
                self?.onCompletion?(job.id, .failure(error))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            finishBackgroundEventsIfNeeded()
        }

        guard let error else { return }
        guard let job = job(for: task) else { return }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            logger.log("Download task cancelled by system — ID: \(job.id)")
            var jobs = loadJobs()
            jobs.removeValue(forKey: job.id)
            saveJobs(jobs)

            Task { @MainActor [weak self] in
                self?.onCompletion?(job.id, .failure(CancellationError()))
            }
            return
        }

        logger.log("Download task completed with error — ID: \(job.id), error: \(error.localizedDescription)")
        var jobs = loadJobs()
        jobs.removeValue(forKey: job.id)
        saveJobs(jobs)

        Task { @MainActor [weak self] in
            self?.onCompletion?(job.id, .failure(error))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        finishBackgroundEventsIfNeeded()
    }
}
