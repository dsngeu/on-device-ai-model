import SwiftUI

struct RecordButtonView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Colors.record.opacity(0.45), lineWidth: 2)
                    .frame(width: 186, height: 186)

                Circle()
                    .fill(AppTheme.Colors.record)
                    .frame(width: 154, height: 154)
                    .shadow(color: AppTheme.Colors.record.opacity(0.45), radius: 24)

                Image(systemName: "mic.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start recording")
    }
}

struct QueueSummaryCardView: View {
    let summary: QueueSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppCard {
                HStack(alignment: .center, spacing: AppTheme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                            .fill(AppTheme.Colors.primaryDim)
                            .frame(width: 40, height: 40)

                        Image(systemName: "hourglass")
                            .foregroundStyle(AppTheme.Colors.primary)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text("Generating notes")
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.text)

                        Text(summary.detailText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
