import Foundation

struct DebriefPaths {
    let documentsURL: URL

    init(fileManager: FileManager = .default) {
        self.documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var appRoot: URL { documentsURL.appendingPathComponent("debrief", isDirectory: true) }
    var recordingsRoot: URL { appRoot.appendingPathComponent("recordings", isDirectory: true) }
    var playbackRoot: URL { appRoot.appendingPathComponent("playback", isDirectory: true) }
    var modelsRoot: URL { documentsURL.appendingPathComponent("models", isDirectory: true) }
    var stateRoot: URL { appRoot.appendingPathComponent("state", isDirectory: true) }

    func recordingDirectory(_ recordingID: String) -> URL {
        recordingsRoot.appendingPathComponent(recordingID, isDirectory: true)
    }

    func segmentsDirectory(_ recordingID: String) -> URL {
        recordingDirectory(recordingID).appendingPathComponent("segments", isDirectory: true)
    }

    func chunksDirectory(_ recordingID: String, segmentID: String) -> URL {
        recordingDirectory(recordingID)
            .appendingPathComponent("chunks", isDirectory: true)
            .appendingPathComponent(segmentID, isDirectory: true)
    }

    func tmpLiveWavDirectory(_ recordingID: String) -> URL {
        recordingDirectory(recordingID)
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("live-wav", isDirectory: true)
    }

    func tmpWavDirectory(_ recordingID: String) -> URL {
        recordingDirectory(recordingID)
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("wav", isDirectory: true)
    }

    func playbackCacheURL(meetingID: String) -> URL {
        playbackRoot.appendingPathComponent("\(meetingID).wav")
    }

    var recordingsStateURL: URL {
        stateRoot.appendingPathComponent("recordings.json")
    }

    var meetingsStateURL: URL {
        stateRoot.appendingPathComponent("meetings.json")
    }

    func relativePath(for url: URL) -> String {
        let path = url.path
        let documentsPath = documentsURL.path
        if path.hasPrefix(documentsPath) {
            return String(path.dropFirst(documentsPath.count + 1))
        }
        return path
    }

    func absoluteURL(for relativePath: String) -> URL {
        documentsURL.appendingPathComponent(relativePath)
    }

    func ensureBaseDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: appRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: recordingsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: playbackRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stateRoot, withIntermediateDirectories: true)
    }
}
