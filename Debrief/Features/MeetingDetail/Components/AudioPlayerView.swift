import SwiftUI

struct AudioPlayerView: View {
    @ObservedObject var playback: AudioPlaybackController
    let meeting: Meeting
    @Environment(\.dismiss) private var dismiss

    @State private var isSeeking = false
    @State private var seekRatio: Double = 0
    @State private var appeared = false
    @State private var glowIntensity: CGFloat = 0

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                closeBar
                Spacer()
                artworkView
                    .padding(.bottom, AppTheme.Spacing.xl)
                titleSection
                Spacer()
                seekBar
                    .padding(.horizontal, AppTheme.Spacing.xl)
                    .padding(.bottom, AppTheme.Spacing.xl)
                transportControls
                    .padding(.bottom, AppTheme.Spacing.xxl)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                appeared = true
            }
            if !playback.isPlaying {
                playback.prepareAndToggle(for: meeting)
            }
        }
        .onDisappear {
            playback.stop()
        }
    }

    // MARK: - Close Bar

    private var closeBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close player")
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.primaryDim)
                .frame(width: 200, height: 200)
                .shadow(
                    color: AppTheme.Colors.primary.opacity(Double(glowIntensity)),
                    radius: 40 * glowIntensity
                )

            waveformBars
        }
        .task(id: playback.isPlaying) {
            if playback.isPlaying {
                await pulseGlow()
            } else {
                withAnimation(.easeOut(duration: 0.5)) {
                    glowIntensity = 0
                }
            }
        }
    }

    private func pulseGlow() async {
        var rising = true
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: 1.2)) {
                glowIntensity = rising ? 0.35 : 0.08
            }
            rising.toggle()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
    }

    private static let barShape: [CGFloat] = [0.5, 0.7, 0.85, 1.0, 0.85, 0.7, 0.5]
    private static let barMinHeight: CGFloat = 8
    private static let barMaxExtra: CGFloat = 44

    private var waveformBars: some View {
        let amp = CGFloat(playback.amplitude)
        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                Capsule()
                    .fill(AppTheme.Colors.primary)
                    .frame(width: 6, height: Self.barMinHeight + Self.barMaxExtra * amp * Self.barShape[i])
            }
        }
        .animation(.easeOut(duration: 0.15), value: playback.amplitude)
    }

    // MARK: - Title

    private var titleSection: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Text(meeting.title)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.Colors.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text("\(meeting.recordedAt.formatted(date: .abbreviated, time: .shortened)) · \(meeting.durationText)")
                .font(.subheadline)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
    }

    // MARK: - Seek Bar

    private var seekBar: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            GeometryReader { geo in
                let width = geo.size.width
                let progress = isSeeking
                    ? seekRatio
                    : (playback.duration > 0 ? playback.currentTime / playback.duration : 0)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.surfaceLight)
                        .frame(height: 6)

                    Capsule()
                        .fill(AppTheme.Colors.primary)
                        .frame(width: max(0, width * progress), height: 6)

                    Circle()
                        .fill(AppTheme.Colors.text)
                        .frame(width: isSeeking ? 18 : 14, height: isSeeking ? 18 : 14)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        .offset(x: clamp(width * progress - (isSeeking ? 9 : 7), min: 0, max: width - (isSeeking ? 18 : 14)))
                        .animation(.interactiveSpring, value: isSeeking)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            seekRatio = clamp(value.location.x / width, min: 0, max: 1)
                        }
                        .onEnded { value in
                            let ratio = clamp(value.location.x / width, min: 0, max: 1)
                            playback.seek(to: ratio)
                            isSeeking = false
                        }
                )
            }
            .frame(height: 20)

            HStack {
                Text(formatTime(isSeeking ? seekRatio * playback.duration : playback.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                Text(formatTime(playback.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: AppTheme.Spacing.xxl) {
            Button { skipBackward() } label: {
                Image(systemName: "gobackward.15")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Colors.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Skip back 15 seconds")

            Button { playback.toggle(for: meeting) } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(AppTheme.Colors.primary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")

            Button { skipForward() } label: {
                Image(systemName: "goforward.15")
                    .font(.title2)
                    .foregroundStyle(AppTheme.Colors.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Skip forward 15 seconds")
        }
    }

    // MARK: - Helpers

    private func skipForward() {
        guard playback.duration > 0 else { return }
        playback.seek(to: clamp((playback.currentTime + 15) / playback.duration, min: 0, max: 1))
    }

    private func skipBackward() {
        guard playback.duration > 0 else { return }
        playback.seek(to: clamp((playback.currentTime - 15) / playback.duration, min: 0, max: 1))
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    private func clamp(_ value: Double, min lo: Double, max hi: Double) -> Double {
        Swift.min(Swift.max(value, lo), hi)
    }
}
