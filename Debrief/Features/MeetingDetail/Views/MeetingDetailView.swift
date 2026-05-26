//feature/meeting-detail/views/meetingdetailview.swift
import SwiftUI

struct MeetingDetailView: View {
    @StateObject var viewModel: MeetingDetailViewModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            if let meeting = viewModel.meeting {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    header(for: meeting)
                    summaryCard(for: meeting)
                    playbackCard(for: meeting)
                    listCard(title: "Action Items", items: meeting.actionItems.map { item in
                        if let person = item.person, !person.isEmpty {
                            return "\(person): \(item.task)"
                        }
                        return item.task
                    })
                    listCard(title: "Key Decisions", items: meeting.keyDecisions)
                    listCard(title: "Open Questions", items: meeting.openQuestions)
                    listCard(title: "Topics", items: meeting.topics)

                    AppCard {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            SectionHeaderView(title: "Transcript")
                            Text(meeting.transcript)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }
                    }

                }
                .padding(AppTheme.Spacing.lg)
            } else {
                EmptyStateView(
                    systemImage: "doc.questionmark",
                    title: "Meeting not found",
                    message: "The requested meeting may have been deleted or has not finished processing yet."
                )
                .padding(AppTheme.Spacing.lg)
            }
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top) {
            if let feedback = viewModel.copyFeedback {
                copyFeedbackBanner(message: feedback.message)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        viewModel.didTapCopyTranscript()
                    } label: {
                        Label("Copy Transcript", systemImage: "text.page")
                    }
                    .disabled(!viewModel.canCopyTranscript)

                    Button {
                        viewModel.didTapCopyFullNote()
                    } label: {
                        Label("Copy Note", systemImage: "doc.on.doc")
                    }
                    .disabled(!viewModel.canCopyFullNote)

                    if viewModel.meeting?.audioPath != nil {
                        Button {
                            viewModel.didTapPlayPause()
                        } label: {
                            Label("Play Audio", systemImage: "play.fill")
                        }
                    }

                    Button {
                        viewModel.didTapReSummarize()
                    } label: {
                        Label("Re-summarize", systemImage: "arrow.clockwise")
                    }

                    Divider()

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Meeting", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body.weight(.medium))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.copyFeedback)
        .confirmationDialog("Delete Meeting", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                viewModel.didTapDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the meeting and its recording. This action cannot be undone.")
        }
        .fullScreenCover(isPresented: $viewModel.showAudioPlayer) {
            if let meeting = viewModel.meeting {
                AudioPlayerView(playback: viewModel.playback, meeting: meeting)
            }
        }
    }

    private func header(for meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(meeting.title)
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.Colors.text)

            HStack(spacing: AppTheme.Spacing.sm) {
                Text(meeting.recordedAt.formatted(date: .abbreviated, time: .shortened))
                Text(meeting.durationText)
            }
            .font(.subheadline)
            .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    private func summaryCard(for meeting: Meeting) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionHeaderView(title: "Summary")
                Text(meeting.summary)
                    .font(.body)
                    .foregroundStyle(AppTheme.Colors.text)

                ForEach(Array(meeting.summaryLines.enumerated()), id: \.offset) { _, line in
                    Text("• \(line)")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
        }
    }

    @ViewBuilder
    private func playbackCard(for meeting: Meeting) -> some View {
        if meeting.audioPath != nil {
            Button {
                viewModel.didTapPlayPause()
            } label: {
                AppCard {
                    HStack(spacing: AppTheme.Spacing.md) {
                        ZStack {
                            Circle()
                                .fill(AppTheme.Colors.primaryDim)
                                .frame(width: 48, height: 48)

                            Image(systemName: viewModel.playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.Colors.primary)
                        }

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                            Text(viewModel.playback.isPlaying ? "Now Playing" : "Play Recording")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.Colors.text)

                            Text(meeting.durationText)
                                .font(.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.Colors.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func listCard(title: String, items: [String]) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                SectionHeaderView(title: title)

                if items.isEmpty {
                    Text("No \(title.lowercased()) yet.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                } else {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Text("• \(item)")
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
    }

    private func copyFeedbackBanner(message: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.Colors.success)

            Text(message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.Colors.text)

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

#Preview {
    let store = AppStore()
    return MeetingDetailView(
        viewModel: MeetingDetailViewModel(
            store: store,
            meetingID: store.meetings.first?.id ?? "",
            onClose: {},
            onOpenQueue: {}
        )
    )
}
