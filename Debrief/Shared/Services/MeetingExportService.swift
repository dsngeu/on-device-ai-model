import Foundation

struct MeetingExportService {
    func plainText(for meeting: Meeting) -> String {
        var lines: [String] = []
        lines.append(meeting.title)
        lines.append("")
        lines.append(meeting.summary)
        lines.append("")

        if !meeting.summaryLines.isEmpty {
            lines.append("Key points")
            meeting.summaryLines.forEach { lines.append("- \($0)") }
            lines.append("")
        }

        if !meeting.actionItems.isEmpty {
            lines.append("Action items")
            meeting.actionItems.forEach { lines.append("- \($0.task)") }
            lines.append("")
        }

        if !meeting.keyDecisions.isEmpty {
            lines.append("Decisions")
            meeting.keyDecisions.forEach { lines.append("- \($0)") }
            lines.append("")
        }

        if !meeting.openQuestions.isEmpty {
            lines.append("Open questions")
            meeting.openQuestions.forEach { lines.append("- \($0)") }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    func markdown(for meeting: Meeting) -> String {
        var lines: [String] = ["# \(meeting.title)", "", meeting.summary, ""]

        if !meeting.summaryLines.isEmpty {
            lines.append("## Key Points")
            meeting.summaryLines.forEach { lines.append("- \($0)") }
            lines.append("")
        }

        if !meeting.actionItems.isEmpty {
            lines.append("## Action Items")
            meeting.actionItems.forEach { lines.append("- \($0.task)") }
            lines.append("")
        }

        if !meeting.keyDecisions.isEmpty {
            lines.append("## Decisions")
            meeting.keyDecisions.forEach { lines.append("- \($0)") }
            lines.append("")
        }

        if !meeting.transcript.isEmpty {
            lines.append("## Transcript")
            lines.append(meeting.transcript)
        }

        return lines.joined(separator: "\n")
    }
}
