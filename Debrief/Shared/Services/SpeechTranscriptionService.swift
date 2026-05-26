import Foundation
import Speech

enum TranscriptionServiceError: LocalizedError {
    case speechPermissionDenied
    case recognizerUnavailable
    case offlineRecognitionUnavailable
    case noTranscript

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            return "Speech recognition permission was denied."
        case .recognizerUnavailable:
            return "Speech recognizer is unavailable for the current locale."
        case .offlineRecognitionUnavailable:
            return "On-device speech recognition is unavailable on this device."
        case .noTranscript:
            return "No transcript was produced for the provided audio."
        }
    }
}

actor SpeechTranscriptionService {
    private var authorizationGranted = false
    private var cachedRecognizer: SFSpeechRecognizer?

    func requestAuthorization() async -> Bool {
        if authorizationGranted { return true }
        log("Requesting speech recognition authorization")
        let granted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        authorizationGranted = granted
        log("Speech authorization result: \(granted ? "granted ✓" : "denied ✗")")
        return granted
    }

    func transcribe(audioURL: URL) async throws -> String {
        let localeIdentifier = Locale.current.identifier
        log("Transcription started — file: \(audioURL.path), locale: \(localeIdentifier)")
        guard await requestAuthorization() else {
            log("Transcription aborted — speech permission denied")
            throw TranscriptionServiceError.speechPermissionDenied
        }

        let recognizer: SFSpeechRecognizer
        if let cached = cachedRecognizer {
            recognizer = cached
        } else if let created = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier)) {
            cachedRecognizer = created
            recognizer = created
        } else {
            log("Transcription aborted — recognizer unavailable for locale: \(localeIdentifier)")
            throw TranscriptionServiceError.recognizerUnavailable
        }

        guard recognizer.supportsOnDeviceRecognition else {
            log("Transcription aborted — on-device recognition not supported")
            throw TranscriptionServiceError.offlineRecognitionUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { continuation in
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if Self.isNoSpeechError(error) {
                        self.log("Transcription produced no speech — \(audioURL.path)")
                        task?.cancel()
                        continuation.resume(throwing: TranscriptionServiceError.noTranscript)
                        return
                    }
                    self.log("Transcription task error — \(audioURL.path): \(error.localizedDescription)")
                    task?.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal else {
                    return
                }

                let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                task?.cancel()
                if transcript.isEmpty {
                    self.log("Transcription produced no text — \(audioURL.path)")
                    continuation.resume(throwing: TranscriptionServiceError.noTranscript)
                } else {
                    self.log("Transcription complete — \(audioURL.path): \(transcript.count) chars")
                    continuation.resume(returning: transcript)
                }
            }
        }
    }

    private static func isNoSpeechError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")

        return message.contains("no speech")
            || message.contains("no speech detected")
            || message.contains("speech not detected")
    }

    private nonisolated func log(_ message: String, file: String = #file, function: String = #function) {
        Task { @MainActor in
            PrintLogger.shared.log(message, file: file, function: function)
        }
    }
}
