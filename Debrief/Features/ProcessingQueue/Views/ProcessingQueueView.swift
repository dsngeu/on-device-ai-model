import SwiftUI

struct ProcessingQueueView: View {
    @StateObject var viewModel: ProcessingQueueViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Processing Queue")
                        .font(.largeTitle.bold())
                        .foregroundStyle(AppTheme.Colors.text)

                    Text("Queue work continues globally, even when this screen is closed.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                if viewModel.items.isEmpty {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: "Nothing in queue",
                        message: "Completed recordings will appear here while local transcription and summary generation run."
                    )
                } else {
                    LazyVStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(viewModel.items) { item in
                            QueueRowView(
                                item: item,
                                onPrimaryAction: { viewModel.didTapPrimaryAction(for: item) },
                                onCancel: { viewModel.didTapCancel(for: item) },
                                onDelete: { viewModel.didTapDelete(for: item) }
                            )
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Delete permanently?",
            isPresented: Binding(
                get: { viewModel.itemPendingDeletion != nil },
                set: { if !$0 { viewModel.cancelDelete() } }
            )
        ) {
            Button("Delete", role: .destructive) { viewModel.confirmDelete() }
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
        } message: {
            if let item = viewModel.itemPendingDeletion {
                Text("\"\(item.title)\" and all its recordings, transcripts, and summaries will be permanently deleted. This cannot be undone.")
            }
        }
    }
}

#Preview {
    ProcessingQueueView(
        viewModel: ProcessingQueueViewModel(
            store: AppStore(),
            onOpenMeeting: { _ in }
        )
    )
}
