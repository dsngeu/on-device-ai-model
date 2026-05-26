import SwiftUI

struct MeetingsView: View {
    @StateObject var viewModel: MeetingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                header
                searchSection
                sortSection
                meetingsSection
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.lg)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle("Meetings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Meetings")
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.Colors.text)

            Text("\(viewModel.totalCount) recording\(viewModel.totalCount == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private var searchSection: some View {
        TextField("Search meetings, topics, summaries...", text: $viewModel.searchText)
            .padding()
            .background(AppTheme.Colors.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .foregroundStyle(AppTheme.Colors.text)
    }

    private var sortSection: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            ForEach(MeetingSortOption.allCases) { option in
                Button(option.rawValue) {
                    viewModel.sortOption = option
                }
                .buttonStyle(.borderedProminent)
                .tint(viewModel.sortOption == option ? AppTheme.Colors.primary : AppTheme.Colors.surfaceLight)
            }
        }
        .font(.caption.weight(.semibold))
    }

    @ViewBuilder
    private var meetingsSection: some View {
        if viewModel.meetings.isEmpty {
            EmptyStateView(
                systemImage: viewModel.searchText.isEmpty ? "mic.circle" : "magnifyingglass.circle",
                title: viewModel.searchText.isEmpty ? "No meetings yet" : "No results found",
                message: viewModel.searchText.isEmpty
                    ? "Record your first conversation to generate local notes."
                    : "Try a different keyword or clear the current search."
            )
        } else {
            LazyVStack(spacing: AppTheme.Spacing.sm) {
                ForEach(viewModel.meetings) { meeting in
                    MeetingRowView(
                        meeting: meeting,
                        onTap: { viewModel.didSelectMeeting(meeting) },
                        onRetry: { viewModel.didTapRetry(meeting) }
                    )
                }
            }
        }
    }
}

#Preview {
    MeetingsView(
        viewModel: MeetingsViewModel(
            store: AppStore(),
            onSelectMeeting: { _ in },
            onOpenQueue: {}
        )
    )
}
