import SwiftUI

struct MeetingRowView: View {
    let meeting: Meeting
    let onTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        Button(action: onTap) {
            AppCard {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(meeting.title)
                                .font(.headline)
                                .foregroundStyle(AppTheme.Colors.text)

                            Text(meeting.recordedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textTertiary)
                        }

                        Spacer()

                        statusChip
                    }

                    Text(meeting.summary)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(3)

                    HStack {
                        Text(meeting.durationText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.Colors.textTertiary)

                        Spacer()

                        if meeting.status != .ready {
                            Button(meeting.status == .failed ? "Retry" : "View queue", action: onRetry)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.primary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var statusChip: some View {
        switch meeting.status {
        case .ready:
            return AnyView(StatusChipView(title: "Ready", tint: AppTheme.Colors.success, background: AppTheme.Colors.successDim))
        case .processing:
            return AnyView(StatusChipView(title: "Processing", tint: AppTheme.Colors.warning, background: AppTheme.Colors.warningDim))
        case .failed:
            return AnyView(StatusChipView(title: "Failed", tint: AppTheme.Colors.error, background: AppTheme.Colors.errorDim))
        case .recorded:
            return AnyView(StatusChipView(title: "Recorded", tint: AppTheme.Colors.primaryLight, background: AppTheme.Colors.primaryDim))
        }
    }
}
