import Foundation

enum AppTab: Hashable {
    case home
    case meetings
    case settings
}

enum AppRoute: Hashable {
    case recording(topic: String?)
    case processingQueue
    case meetingDetail(id: String)
}

enum MeetingStatus: String, Hashable, Codable {
    case recorded
    case processing
    case ready
    case failed
}

enum RecordingQueueState: String, Hashable, Codable {
    case queued
    case paused
    case failed
}

enum LiveTranscriptStatus: String, Codable, Hashable {
    case idle
    case waitingChunks
    case transcribing
    case noModel
    case unavailable
    case error
}

enum RecordingStage: String, Codable, Hashable {
    case idle
    case recording
    case paused
    case transcribing
    case done
    case error
}

enum QueuePhase: String, Codable, Hashable {
    case idle
    case transcribing
    case summarizing
}

enum ModelStatus: String, Codable, Hashable {
    case notDownloaded = "not_downloaded"
    case downloading = "downloading"
    case downloaded = "downloaded"
    case active
}

struct ActionItem: Identifiable, Hashable, Codable {
    let id: String
    let person: String?
    let task: String
    let dueDate: String?
    var completed: Bool
}

struct RawActionItem: Hashable, Codable {
    let person: String?
    let task: String
    let dueDate: String?
}

struct MeetingSummary: Hashable, Codable {
    var title: String
    var summary: String
    var summaryLines: [String]
    var actionItems: [RawActionItem]
    var keyDecisions: [String]
    var openQuestions: [String]
    var topics: [String]
}

struct Meeting: Identifiable, Hashable, Codable {
    let id: String
    var title: String
    var summary: String
    var summaryLines: [String]
    var actionItems: [ActionItem]
    var keyDecisions: [String]
    var openQuestions: [String]
    var topics: [String]
    var transcript: String
    var meetingTopic: String?
    var participants: [String]
    var duration: Int
    var recordedAt: Date
    var modelUsed: String
    var audioPath: String?
    var status: MeetingStatus
    var processingError: String?

    var durationText: String {
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }

        return "\(seconds)s"
    }
}

struct RecordingSession: Identifiable, Hashable, Codable {
    let id: String
    var createdAt: Date
    var updatedAt: Date
    var meetingTopic: String?
    var participants: [String]
    var durationSeconds: Int
    var isRecordingComplete: Bool
    var isProcessing: Bool
    var queueState: RecordingQueueState?
    var transcript: String
    var lastProcessedChunkTimestamp: Int64?
    var meetingID: String?
    var processingError: String?
    var audioRelativePath: String?
}

struct QueueItem: Identifiable, Hashable {
    let id: String
    let meetingID: String?
    var title: String
    var state: QueueItemState
    var progress: Double
    var subtitle: String
    var createdAt: Date
}

enum QueueItemState: String, Hashable {
    case queued
    case transcribing
    case summarizing
    case paused
    case failed
    case done
}

struct SummaryModel: Hashable, Codable {
    let id: String
    let name: String
    let size: String
    let sizeBytes: Int64
    let description: String
    let downloadURL: URL
}

struct ModelDownloadState: Hashable, Codable {
    var status: ModelStatus = .notDownloaded
    var progress: Double = 0
}

struct AppSettings: Hashable, Codable {
    /// Legacy single-model state; migrated to summaryModelStates on load.
    private var summaryModelState = ModelDownloadState()

    /// Selected summary model ID. Default: Qwen 2.5 1.5B.
    var selectedSummaryModelID: String = "qwen2.5-1.5b-instruct"

    /// Per-model download state keyed by model ID.
    var summaryModelStates: [String: ModelDownloadState] = [:]

    enum CodingKeys: String, CodingKey {
        case summaryModelState
        case selectedSummaryModelID
        case summaryModelStates
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summaryModelState = try container.decodeIfPresent(ModelDownloadState.self, forKey: .summaryModelState) ?? ModelDownloadState()
        selectedSummaryModelID = try container.decodeIfPresent(String.self, forKey: .selectedSummaryModelID) ?? "qwen2.5-1.5b-instruct"
        summaryModelStates = try container.decodeIfPresent([String: ModelDownloadState].self, forKey: .summaryModelStates) ?? [:]

        // Migrate legacy single-model state to per-model states
        if summaryModelStates.isEmpty && summaryModelState.status != .notDownloaded {
            summaryModelStates["qwen2.5-1.5b-instruct"] = summaryModelState
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selectedSummaryModelID, forKey: .selectedSummaryModelID)
        try container.encode(summaryModelStates, forKey: .summaryModelStates)
    }
}

struct ProcessingQueueStatus: Hashable, Codable {
    var activeRecordingID: String?
    var progress: Double = 0
    var phase: QueuePhase = .idle
}

struct RecordingRuntimeState: Hashable {
    var recordingID: String?
    var topic: String?
    var stage: RecordingStage = .idle
    var durationSeconds = 0
    var amplitude: Double = 0
    var liveTranscript = ""
    var liveStatus: LiveTranscriptStatus = .idle
    var chunksReceived = 0
    var chunksTranscribed = 0
    var lastChunkAt: Date?
    var errorMessage: String?
    var interruptionMessage: String?
}
