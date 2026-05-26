import SwiftUI

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                header
                onboardingBanner
                recordSection

                if viewModel.queueSummary.total > 0 {
                    QueueSummaryCardView(summary: viewModel.queueSummary) {
                        viewModel.didTapQueue()
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("Debrief")
                    .font(.largeTitle.bold())
                    .foregroundStyle(AppTheme.Colors.text)

                Text("Local-first meeting capture and AI notes.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer()

            StatusChipView(
                title: "On-device",
                tint: AppTheme.Colors.success,
                background: AppTheme.Colors.successDim
            )
        }
    }

    private var onboardingBanner: some View {
        Group {
            if !viewModel.hasDownloadedModel {
                Button(action: viewModel.didTapSettingsBanner) {
                    AppCard {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(AppTheme.Colors.warning)

                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                Text("Download the summary model")
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.Colors.warning)

                                Text("Go to Settings to install the summary model before your first recording.")
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recordSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            RecordButtonView {
                viewModel.didTapRecord()
            }

            Text("Tap to start recording")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.Colors.textTertiary)
                .frame(maxWidth: .infinity)

            Text("Debrief will generate the meeting title after notes are ready.")
                .font(.footnote)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}

#Preview {
    HomeView(
        viewModel: HomeViewModel(
            store: AppStore(),
            onStartRecording: { _ in },
            onOpenQueue: {},
            onOpenSettings: {}
        )
    )
}
