import SwiftUI

struct RecordingView: View {
    @StateObject var viewModel: RecordingViewModel
    @State private var showDiscardAlert = false
    @State private var showLiveTranscript = false
    private let controlsReserve: CGFloat = 132

    private var isActive: Bool {
        viewModel.stage == .recording
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                recorderContent(in: geometry)
                    .blur(radius: showLiveTranscript ? 10 : 0)
                    .scaleEffect(showLiveTranscript ? 0.985 : 1.0)
                    .allowsHitTesting(!showLiveTranscript)

                if showLiveTranscript {
                    Color.black
                        .opacity(0.22)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .onTapGesture(perform: toggleTranscriptOverlay)
                }

                VStack {
                    HStack {
                        Spacer()

                        RecordingTopBarButton(isPresented: showLiveTranscript) {
                            toggleTranscriptOverlay()
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, geometry.safeAreaInsets.top + AppTheme.Spacing.sm)

                    Spacer()
                }

                if showLiveTranscript {
                    VStack {
                        HStack {
                            Spacer()

                            LiveTranscriptOverlayView(
                                transcript: viewModel.liveTranscript,
                                chunksReceived: viewModel.chunksReceived,
                                chunksTranscribed: viewModel.chunksTranscribed,
                                errorMessage: viewModel.errorMessage,
                                maximumHeight: transcriptOverlayHeight(in: geometry),
                                dismiss: toggleTranscriptOverlay
                            )
                        }
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.top, geometry.safeAreaInsets.top + 64)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .alert("Discard recording?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) { viewModel.didTapDiscard() }
            Button("Keep Recording", role: .cancel) {}
        } message: {
            Text("This recording and any live transcript will be permanently deleted.")
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: showLiveTranscript)
    }

    private func recorderContent(in geometry: GeometryProxy) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer()

                AmplitudeVisualizerView(
                    amplitude: viewModel.amplitude,
                    isActive: isActive
                )
                .frame(height: 250)

                timerSection
                    .padding(.top, AppTheme.Spacing.md)

                statusRow
                    .padding(.top, AppTheme.Spacing.sm)

                Text("Meeting title will be generated after processing.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.Colors.textTertiary)
                    .padding(.top, AppTheme.Spacing.xs)

                Spacer()
            }
            .padding(.bottom, min(controlsReserve, geometry.size.height * 0.2))

            controlBar
                .padding(.bottom, AppTheme.Spacing.xl)
        }
    }

    private func toggleTranscriptOverlay() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            showLiveTranscript.toggle()
        }
    }

    private func transcriptOverlayHeight(in geometry: GeometryProxy) -> CGFloat {
        let safeTop = geometry.safeAreaInsets.top
        let reservedBottom = max(controlsReserve + AppTheme.Spacing.xl, geometry.size.height * 0.22)
        let availableHeight = geometry.size.height - safeTop - reservedBottom - 96
        let preferredHeight = geometry.size.height * 0.58

        return max(220, min(preferredHeight, availableHeight))
    }

    // MARK: - Timer

    private var timerSection: some View {
        Text(viewModel.elapsedText)
            .font(.system(size: 54, weight: .thin, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AppTheme.Colors.text)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.15), value: viewModel.elapsedSeconds)
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 6) {
            if isActive {
                PulsingDotView()
            } else if viewModel.stage == .paused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(AppTheme.Colors.warning)
            }

            Text(viewModel.statusText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(statusColor)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.stage)
    }

    private var statusColor: Color {
        switch viewModel.stage {
        case .recording: AppTheme.Colors.record
        case .paused: AppTheme.Colors.warning
        case .error: AppTheme.Colors.error
        default: AppTheme.Colors.textSecondary
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        HStack(spacing: AppTheme.Spacing.xl) {
            RecordingControlButton(
                icon: "xmark",
                label: "Discard",
                size: 50,
                iconSize: 17,
                foreground: AppTheme.Colors.error,
                background: AppTheme.Colors.errorDim,
                action: { showDiscardAlert = true }
            )

            RecordingControlButton(
                icon: "stop.fill",
                label: "Save",
                size: 72,
                iconSize: 24,
                foreground: .white,
                background: AppTheme.Colors.success,
                action: { viewModel.didTapStop() }
            )

            RecordingControlButton(
                icon: viewModel.stage == .paused ? "play.fill" : "pause.fill",
                label: viewModel.stage == .paused ? "Resume" : "Pause",
                size: 50,
                iconSize: 17,
                foreground: AppTheme.Colors.primary,
                background: AppTheme.Colors.primaryDim,
                action: { viewModel.didTapPauseResume() }
            )
        }
    }
}

#Preview {
    RecordingView(
        viewModel: RecordingViewModel(
            store: AppStore(),
            initialTopic: "Weekly sync",
            onFinish: {}
        )
    )
}
