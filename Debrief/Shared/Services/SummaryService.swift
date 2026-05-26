import Foundation
import NaturalLanguage

struct SummaryService: Sendable {
    nonisolated func summarize(transcript: String, topic: String?, participants: [String]) -> MeetingSummary {
        log("Summarization started — transcript: \(transcript.count) chars, topic: \(topic ?? "(none)"), participants: \(participants.count)")
        let cleaned = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            log("Summarization — transcript is empty, returning empty summary")
            return MeetingSummary(
                title: topic?.isEmpty == false ? topic! : "No speech detected",
                summary: "No usable speech was detected in the recording, so Debrief could not build a detailed note.",
                summaryLines: ["The recording completed, but no recognizable speech was available for summarization."],
                actionItems: [],
                keyDecisions: [],
                openQuestions: [],
                topics: topic.map { [$0] } ?? []
            )
        }

        let sentences = splitSentences(cleaned)
        log("Summarization — sentences found: \(sentences.count)")
        let importantSentences = Array(sentences.prefix(4))
        let title = buildTitle(topic: topic, transcript: cleaned)
        let summary = importantSentences.prefix(2).joined(separator: " ")
        let summaryLines = importantSentences.isEmpty ? [summary] : importantSentences
        let actionItems = extractActionItems(from: sentences)
        let openQuestions = sentences.filter { $0.contains("?") }.prefix(3).map { $0 }
        let keyDecisions = extractDecisions(from: sentences)
        let topics = extractTopics(from: cleaned, topic: topic, participants: participants)

        log("Summarization complete ✓ — title: \"\(title)\", actionItems: \(actionItems.count), decisions: \(keyDecisions.count), questions: \(openQuestions.count), topics: \(topics)")

        return MeetingSummary(
            title: title,
            summary: summary.isEmpty ? cleaned : summary,
            summaryLines: summaryLines,
            actionItems: actionItems,
            keyDecisions: keyDecisions,
            openQuestions: Array(openQuestions),
            topics: topics
        )
    }

    private nonisolated func splitSentences(_ text: String) -> [String] {
        text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .split(separator: ".")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix("?") || $0.hasSuffix("!") ? $0 : $0 + "." }
    }

    private nonisolated func buildTitle(topic: String?, transcript: String) -> String {
        if let topic, !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return topic
        }

        let tokens = transcript
            .split(separator: " ")
            .prefix(6)
            .map(String.init)

        return tokens.isEmpty ? "Untitled meeting" : tokens.joined(separator: " ")
    }

    private nonisolated func extractActionItems(from sentences: [String]) -> [RawActionItem] {
        let verbs = ["follow up", "send", "share", "review", "prepare", "schedule", "confirm", "update", "create"]

        return sentences.compactMap { sentence in
            let lower = sentence.lowercased()
            guard verbs.contains(where: lower.contains) else { return nil }
            return RawActionItem(person: nil, task: sentence, dueDate: nil)
        }
        .prefix(5)
        .map { $0 }
    }

    private nonisolated func extractDecisions(from sentences: [String]) -> [String] {
        sentences.filter { sentence in
            let lower = sentence.lowercased()
            return lower.contains("decided") || lower.contains("agreed") || lower.contains("will ")
        }
        .prefix(4)
        .map { $0 }
    }

    private nonisolated func extractTopics(from transcript: String, topic: String?, participants: [String]) -> [String] {
        var tags: [String] = []
        if let topic, !topic.isEmpty {
            tags.append(topic)
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = transcript
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        var frequencies: [String: Int] = [:]
        let excluded = Set(["the", "and", "for", "that", "with", "this", "from", "have", "will", "were", "they", "them"])

        tagger.enumerateTags(in: transcript.startIndex..<transcript.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            guard tag == .noun || tag == .otherWord else {
                return true
            }
            let word = String(transcript[range]).lowercased()
            guard word.count > 3, !excluded.contains(word) else {
                return true
            }
            frequencies[word, default: 0] += 1
            return true
        }

        let topWords = frequencies
            .sorted { lhs, rhs in lhs.value > rhs.value }
            .prefix(4)
            .map(\.key.capitalized)

        tags.append(contentsOf: topWords)
        tags.append(contentsOf: participants.prefix(2))

        return Array(NSOrderedSet(array: tags).array as? [String] ?? [])
    }

    private nonisolated func log(_ message: String, file: String = #file, function: String = #function) {
        Task { @MainActor in
            PrintLogger.shared.log(message, file: file, function: function)
        }
    }
}
