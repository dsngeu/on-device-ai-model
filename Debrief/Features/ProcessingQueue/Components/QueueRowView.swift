import SwiftUI

struct QueueRowView: View {
    let item: QueueItem
    let onPrimaryAction: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.text)

                        Text(item.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }

                    Spacer()

                    chip
                }

                ProgressView(value: item.progress)
                    .tint(AppTheme.Colors.primary)

                HStack {
                    Button(primaryButtonTitle, action: onPrimaryAction)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.Colors.primary)

                    if item.state != .done {
                        Button("Cancel", role: .destructive, action: onCancel)
                            .buttonStyle(.bordered)
                    }

                    Spacer()

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.Colors.error)
                }
                .font(.caption.weight(.semibold))
            }
        }
    }

    private var primaryButtonTitle: String {
        switch item.state {
        case .paused:
            return "Resume"
        case .failed:
            return "Retry"
        case .done:
            return "Open"
        default:
            return "Pause"
        }
    }

    private var chip: some View {
        let config: (Color, Color) = switch item.state {
        case .failed: (AppTheme.Colors.error, AppTheme.Colors.errorDim)
        case .paused: (AppTheme.Colors.warning, AppTheme.Colors.warningDim)
        case .done: (AppTheme.Colors.success, AppTheme.Colors.successDim)
        default: (AppTheme.Colors.primaryLight, AppTheme.Colors.primaryDim)
        }

        return StatusChipView(title: item.state.rawValue.capitalized, tint: config.0, background: config.1)
    }
}
