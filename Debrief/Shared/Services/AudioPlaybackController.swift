import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var isPreparing = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var amplitude: Float = 0

    private let paths = DebriefPaths()
    private let converter = AudioConversionService()
    private let logger = PrintLogger.shared
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func prepareAndToggle(for meeting: Meeting) {
        logger.log("Preparing audio playback — meeting: \(meeting.id), title: \"\(meeting.title)\"")
        Task {
            do {
                isPreparing = true
                try configureAudioSessionForPlayback()
                let audioURL = try playableURL(for: meeting)
                let player = try AVAudioPlayer(contentsOf: audioURL)
                player.delegate = self
                player.isMeteringEnabled = true
                player.prepareToPlay()
                self.player = player
                duration = player.duration
                if isPlaying {
                    logger.log("Pausing audio playback — meeting: \(meeting.id)")
                    player.pause()
                    isPlaying = false
                } else {
                    logger.log("Starting audio playback ✓ — meeting: \(meeting.id), duration: \(String(format: "%.1f", player.duration))s")
                    player.play()
                    isPlaying = true
                    startTimer()
                }
                isPreparing = false
            } catch {
                logger.log("Audio playback preparation failed — meeting: \(meeting.id), error: \(error.localizedDescription)")
                isPreparing = false
            }
        }
    }

    func toggle(for meeting: Meeting) {
        if let player {
            if isPlaying {
                player.pause()
                isPlaying = false
                timer?.invalidate()
                timer = nil
            } else {
                player.play()
                isPlaying = true
                startTimer()
            }
        } else {
            prepareAndToggle(for: meeting)
        }
    }

    func seek(to ratio: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(player.duration, player.duration * ratio))
        currentTime = player.currentTime
        logger.log("Audio seek — position: \(String(format: "%.1f", currentTime))s / \(String(format: "%.1f", player.duration))s")
    }

    func stop() {
        logger.log("Audio playback stopped")
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        amplitude = 0
        timer?.invalidate()
        timer = nil
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        logger.log("Audio playback finished — success: \(flag)")
        isPlaying = false
        amplitude = 0
        timer?.invalidate()
        timer = nil
        currentTime = 0
    }

    private func configureAudioSessionForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        logger.log("Audio session configured for playback — routing to speaker")
    }

    private func playableURL(for meeting: Meeting) throws -> URL {
        guard let audioPath = meeting.audioPath else {
            logger.log("Audio file not found — meeting: \(meeting.id)")
            throw NSError(domain: "DebriefPlayback", code: 404, userInfo: [NSLocalizedDescriptionKey: "Audio file not found."])
        }

        let absoluteURL = paths.absoluteURL(for: audioPath)
        if ["wav", "m4a", "mp3"].contains(absoluteURL.pathExtension.lowercased()) {
            logger.log("Using native audio format for playback: \(absoluteURL.path)")
            return absoluteURL
        }

        let cacheURL = paths.playbackCacheURL(meetingID: meeting.id)
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            logger.log("Playback cache miss — converting PCM to WAV for meeting: \(meeting.id)")
            try converter.convertPCMToWAV(inputURL: absoluteURL, outputURL: cacheURL)
            logger.log("Playback WAV cached — \(cacheURL.path)")
        } else {
            logger.log("Using cached playback WAV — \(cacheURL.path)")
        }
        return cacheURL
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(updatePlaybackProgress), userInfo: nil, repeats: true)
    }

    @objc
    private func updatePlaybackProgress() {
        guard let player else { return }
        currentTime = player.currentTime
        duration = player.duration
        player.updateMeters()
        let dB = player.averagePower(forChannel: 0)
        amplitude = max(0, (dB + 50) / 50)
    }
}
