//feature/settings/views/settingsview.swift
import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Settings")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.Colors.text)

                    Text("Models, storage preferences, and privacy controls.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                if let downloadErrorMessage = viewModel.downloadErrorMessage {
                    AppCard {
                        Text(downloadErrorMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.error)
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        SectionHeaderView(title: "Summary Model")
                        Text("Choose a model for meeting summaries. Download and switch between models below.")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        ForEach(Array(viewModel.availableSummaryModels.enumerated()), id: \.element.id) { index, model in
                            if index > 0 {
                                Divider()
                                    .padding(.vertical, AppTheme.Spacing.xs)
                            }
                            SummaryModelRowView(
                                model: model,
                                isSelected: viewModel.settings.selectedSummaryModelID == model.id,
                                state: viewModel.modelState(for: model.id),
                                onSelect: { viewModel.didSelectSummaryModel(modelID: model.id) },
                                onAction: { viewModel.didTapSummaryModel(modelID: model.id) }
                            )
                        }
                    }
                }

                AppCard {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionHeaderView(title: "Privacy")
                        Text("All recordings, transcripts, and summaries are kept on-device for privacy")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

}

private struct SummaryModelRowView: View {
    let model: SummaryModel
    let isSelected: Bool
    let state: ModelDownloadState
    let onSelect: () -> Void
    let onAction: () -> Void

    private var statusTitle: String {
        switch state.status {
        case .downloaded, .active:
            return "Installed"
        case .downloading:
            return "Downloading"
        case .notDownloaded:
            return "Not Installed"
        }
    }

    private var actionTitle: String {
        switch state.status {
        case .downloaded, .active:
            return "Remove"
        case .downloading:
            return "Cancel"
        case .notDownloaded:
            return "Download"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        Text(model.name)
                            .font(.headline)
                            .foregroundStyle(AppTheme.Colors.text)
                        if isSelected {
                            Text("In use")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppTheme.Colors.primary.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    Text(model.description)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text(model.size)
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer()

                if !isSelected {
                    Button("Use") {
                        onSelect()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.Colors.primary)
                }
            }

            HStack {
                StatusChipView(
                    title: statusTitle,
                    tint: state.status == .downloaded || state.status == .active ? AppTheme.Colors.success : AppTheme.Colors.warning,
                    background: state.status == .downloaded || state.status == .active ? AppTheme.Colors.successDim : AppTheme.Colors.warningDim
                )

                Spacer()

                Button(actionTitle) {
                    onAction()
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.Colors.primary)
            }
            .font(.caption.weight(.semibold))

            if state.status == .downloading {
                ProgressView(value: state.progress)
                    .tint(AppTheme.Colors.primary)
                Text("\(Int(state.progress * 100))% downloaded")
                    .font(.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

#Preview {
    SettingsView(viewModel: SettingsViewModel(store: AppStore()))
}
