import Foundation
import LlamaSwift

/// Summarizes meeting transcripts using a local GGUF model (Qwen 2.5 1.5B).
/// Runs inference off the main thread. Falls back to heuristic parsing if model output is unparseable.
actor LLMSummarizationService {
    private let logger = PrintLogger.shared
    private let fallback = SummaryService()

    private static let maxContextTokens = 2048
    private static let maxOutputTokens = 512
    private static let nBatch = 256

    /// Summarize transcript using the GGUF model at the given URL.
    /// Falls back to heuristic summarization if model fails to load or generate.
    func summarize(
        transcript: String,
        topic: String?,
        participants: [String],
        modelURL: URL
    ) async -> MeetingSummary {
        let cleaned = transcript
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else {
            return MeetingSummary(
                title: topic ?? "No speech detected",
                summary: "No usable speech was detected in the recording.",
                summaryLines: ["The recording completed, but no recognizable speech was available."],
                actionItems: [],
                keyDecisions: [],
                openQuestions: [],
                topics: topic.map { [$0] } ?? []
            )
        }

        let result = await Task.detached(priority: .userInitiated) {
            self.runInference(transcript: cleaned, topic: topic, participants: participants, modelPath: modelURL.path)
        }.value

        if let summary = result {
            logger.log("LLM summarization complete ✓ — title: \"\(summary.title)\", actionItems: \(summary.actionItems.count)")
            return summary
        }

        logger.log("LLM summarization failed — falling back to heuristic")
        return fallback.summarize(transcript: transcript, topic: topic, participants: participants)
    }

    private nonisolated func runInference(
        transcript: String,
        topic: String?,
        participants: [String],
        modelPath: String
    ) -> MeetingSummary? {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            return nil
        }

        let prompt = buildPrompt(transcript: transcript, topic: topic, participants: participants)
        let truncatedTranscript = String(transcript.prefix(6000))
        let fullPrompt = buildPrompt(transcript: truncatedTranscript, topic: topic, participants: participants)

        return withInferenceContext(modelPath: modelPath) { model, context, vocab in
            generateAndParse(prompt: fullPrompt, model: model, context: context, vocab: vocab, topic: topic)
        }
    }

    private nonisolated func buildPrompt(transcript: String, topic: String?, participants: [String]) -> String {
        let topicLine = topic.map { "Meeting topic: \($0)\n" } ?? ""
        let participantsLine = participants.isEmpty ? "" : "Participants: \(participants.joined(separator: ", "))\n"
        return """
        You will extract structured meeting notes from a transcript. Output in the style of professional meeting tools like Otter.ai.

        \(topicLine)\(participantsLine)Transcript:
        \(transcript)

        Return ONLY valid JSON matching this schema:
        {
          "title": "Concise meeting title (5-8 words)",
          "summary": "2-4 sentence prose paragraph. State who attended (if mentioned), what was discussed, key outcomes, and important context. Write in third person, past tense.",
          "summaryLines": ["3-6 key discussion points as concise bullet sentences. Each must be a complete, specific statement — not a vague label."],
          "actionItems": [{"person": "name or empty string", "task": "specific task description", "dueDate": "date or empty string"}],
          "keyDecisions": ["Decision made, phrased as a complete sentence"],
          "openQuestions": ["Unresolved question or open item that needs follow-up, phrased as a question"],
          "topics": ["Short topic label"]
        }

        Rules:
        - summary must be flowing prose, not bullet points.
        - summaryLines must be informative statements, not topic headings.
        - openQuestions should capture things that were raised but not resolved.
        - If a field has no content, use an empty array or empty string.
        - Do not include any text outside the JSON.
        """
    }

    private nonisolated func withInferenceContext<T>(
        modelPath: String,
        body: (OpaquePointer, OpaquePointer, OpaquePointer) -> T?
    ) -> T? {
        llama_backend_init()
        defer { llama_backend_free() }

        var modelParams = llama_model_default_params()
        guard let model = llama_model_load_from_file(modelPath, modelParams) else {
            return nil
        }
        defer { llama_model_free(model) }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(Self.maxContextTokens)
        contextParams.n_batch = UInt32(Self.nBatch)

        guard let context = llama_init_from_model(model, contextParams) else {
            return nil
        }
        defer { llama_free(context) }

        guard let vocab = llama_model_get_vocab(model) else {
            return nil
        }
        return body(model, context, vocab)
    }

    private nonisolated func generateAndParse(
        prompt: String,
        model: OpaquePointer,
        context: OpaquePointer,
        vocab: OpaquePointer,
        topic: String?
    ) -> MeetingSummary? {
        let promptUtf8 = prompt.utf8
        let maxTokens = promptUtf8.count + 1
        var tokens = [llama_token](repeating: 0, count: maxTokens)

        let tokenCount = llama_tokenize(
            vocab,
            prompt,
            Int32(promptUtf8.count),
            &tokens,
            Int32(maxTokens),
            true,
            true
        )

        guard tokenCount > 0 else { return nil }

        let promptTokens = Array(tokens.prefix(Int(tokenCount)))
        let nPromptTokens = min(promptTokens.count, Self.maxContextTokens - Self.maxOutputTokens)

        var batch = llama_batch_init(Int32(Self.nBatch), 0, 1)
        defer { llama_batch_free(batch) }

        // Process prompt in chunks of nBatch — batch is only allocated for 256 tokens
        var nCur: Int32 = 0
        var chunkStart = 0
        while chunkStart < nPromptTokens {
            let chunkEnd = min(chunkStart + Self.nBatch, nPromptTokens)
            let chunkSize = chunkEnd - chunkStart
            batch.n_tokens = Int32(chunkSize)

            for i in 0..<chunkSize {
                let idx = Int(i)
                let tokenIdx = chunkStart + idx
                batch.token[idx] = promptTokens[tokenIdx]
                batch.pos[idx] = nCur + Int32(idx)
                batch.n_seq_id[idx] = 1
                if let seqIds = batch.seq_id, let seqId = seqIds[idx] {
                    seqId[0] = 0
                }
                batch.logits[idx] = 0
            }
            if chunkSize > 0 {
                batch.logits[chunkSize - 1] = 1
            }
            nCur += Int32(chunkSize)

            guard llama_decode(context, batch) == 0 else { return nil }
            chunkStart = chunkEnd
        }

        var generated = ""
        let eosToken = llama_vocab_eos(vocab)
        let vocabSize = llama_vocab_n_tokens(vocab)

        for _ in 0..<Self.maxOutputTokens {
            guard let logits = llama_get_logits_ith(context, -1) else { break }

            var maxLogit = logits[0]
            var nextToken: llama_token = 0
            for i in 1..<Int(vocabSize) {
                if logits[i] > maxLogit {
                    maxLogit = logits[i]
                    nextToken = llama_token(i)
                }
            }

            if nextToken == eosToken { break }

            var buffer = [CChar](repeating: 0, count: 32)
            let length = llama_token_to_piece(vocab, nextToken, &buffer, Int32(buffer.count), 0, false)
            if length > 0 {
                generated += String(cString: buffer)
            }

            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = nCur
            batch.n_seq_id[0] = 1
            if let seqIds = batch.seq_id, let seqId = seqIds[0] {
                seqId[0] = 0
            }
            batch.logits[0] = 1
            nCur += 1

            guard llama_decode(context, batch) == 0 else { break }
        }

        return parseGeneratedOutput(generated, topic: topic)
    }

    private nonisolated func parseGeneratedOutput(_ text: String, topic: String?) -> MeetingSummary? {
        if let json = parseJsonOutput(text, topic: topic) {
            return json
        }
        return parseLegacyOutput(text, topic: topic)
    }

    /// Extracts and parses JSON from model output. Handles markdown code blocks and trailing text.
    private nonisolated func parseJsonOutput(_ text: String, topic: String?) -> MeetingSummary? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var jsonStr = trimmed
        if let start = trimmed.range(of: "```json") {
            jsonStr = String(trimmed[start.upperBound...])
        } else if let start = trimmed.range(of: "```") {
            jsonStr = String(trimmed[start.upperBound...])
        }
        if let end = jsonStr.range(of: "```") {
            jsonStr = String(jsonStr[..<end.lowerBound])
        }
        if let firstBrace = jsonStr.firstIndex(of: "{") {
            var depth = 1
            var endIndex = jsonStr.endIndex
            var currentIndex = jsonStr.index(after: firstBrace)
            while currentIndex < jsonStr.endIndex {
                let c = jsonStr[currentIndex]
                if c == "{" { depth += 1 }
                else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = jsonStr.index(after: currentIndex)
                        break
                    }
                }
                currentIndex = jsonStr.index(after: currentIndex)
            }
            jsonStr = String(jsonStr[firstBrace..<endIndex])
        }

        guard let data = jsonStr.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()

        struct JsonActionItem: Codable {
            let person: String?
            let task: String?
            let dueDate: String?
        }
        struct JsonSummary: Codable {
            let title: String?
            let summary: String?
            let summaryLines: [String]?
            let actionItems: [JsonActionItem]?
            let keyDecisions: [String]?
            let openQuestions: [String]?
            let topics: [String]?
        }

        guard let parsed = try? decoder.decode(JsonSummary.self, from: data) else { return nil }

        let title = parsed.title?.trimmingCharacters(in: .whitespaces).notEmpty ?? topic ?? "Meeting notes"
        let summary = parsed.summary?.trimmingCharacters(in: .whitespaces) ?? ""
        let summaryLines = parsed.summaryLines?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        let actionItems = parsed.actionItems?.compactMap { item -> RawActionItem? in
            let task = (item.task ?? "").trimmingCharacters(in: .whitespaces)
            guard !task.isEmpty else { return nil }
            return RawActionItem(
                person: item.person.flatMap { $0.trimmingCharacters(in: .whitespaces).notEmpty },
                task: task,
                dueDate: item.dueDate.flatMap { $0.trimmingCharacters(in: .whitespaces).notEmpty }
            )
        } ?? []
        let keyDecisions = parsed.keyDecisions?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        let openQuestions = parsed.openQuestions?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        let topics = parsed.topics?.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []

        if summary.isEmpty && actionItems.isEmpty && keyDecisions.isEmpty {
            return nil
        }

        return MeetingSummary(
            title: title,
            summary: summary.isEmpty ? (actionItems.first?.task ?? "Summary generated.") : summary,
            summaryLines: summaryLines.isEmpty ? (summary.isEmpty ? ["Meeting summarized."] : [summary]) : summaryLines,
            actionItems: actionItems,
            keyDecisions: keyDecisions,
            openQuestions: openQuestions,
            topics: topics.isEmpty && topic != nil ? [topic!] : topics
        )
    }

    private nonisolated func parseLegacyOutput(_ text: String, topic: String?) -> MeetingSummary? {
        var title = topic ?? "Meeting notes"
        var summary = ""
        var actionItems: [RawActionItem] = []
        var keyDecisions: [String] = []
        var openQuestions: [String] = []
        var topics: [String] = []

        let lines = text.components(separatedBy: .newlines)
        var currentSection = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            if trimmed.uppercased().hasPrefix("TITLE:") {
                title = trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if title.isEmpty { title = "Meeting notes" }
            } else if trimmed.uppercased().hasPrefix("SUMMARY:") {
                summary = trimmed.dropFirst(8).trimmingCharacters(in: .whitespaces)
            } else if trimmed.uppercased().hasPrefix("ACTION_ITEMS:") {
                currentSection = "action"
            } else if trimmed.uppercased().hasPrefix("KEY_DECISIONS:") {
                currentSection = "decisions"
            } else if trimmed.uppercased().hasPrefix("OPEN_QUESTIONS:") {
                currentSection = "questions"
            } else if trimmed.uppercased().hasPrefix("TOPICS:") {
                let raw = trimmed.dropFirst(7).trimmingCharacters(in: .whitespaces)
                topics = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                currentSection = ""
            } else if trimmed.hasPrefix("- ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                switch currentSection {
                case "action": actionItems.append(RawActionItem(person: nil, task: content, dueDate: nil))
                case "decisions": keyDecisions.append(content)
                case "questions": openQuestions.append(content)
                default: break
                }
            }
        }

        if summary.isEmpty && actionItems.isEmpty && keyDecisions.isEmpty {
            return nil
        }

        let summaryLines = summary.isEmpty ? [] : summary.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) + "." }.filter { !$0.isEmpty }
        return MeetingSummary(
            title: title,
            summary: summary.isEmpty ? (actionItems.first?.task ?? "Summary generated.") : summary,
            summaryLines: summaryLines.isEmpty ? [summary.isEmpty ? "Meeting summarized." : summary] : summaryLines,
            actionItems: actionItems,
            keyDecisions: keyDecisions,
            openQuestions: openQuestions,
            topics: topics.isEmpty && topic != nil ? [topic!] : topics
        )
    }
}

private extension String {
    var notEmpty: String? {
        let t = trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }
}
