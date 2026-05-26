import SwiftUI

// MARK: - Amplitude Visualizer

struct AmplitudeVisualizerView: View {
    let amplitude: Double
    let isActive: Bool

    @State private var displayedAmplitude: Double = 0
    @State private var pulsePhase = false

    private let ringCount = 3

    private var normalizedAmplitude: Double {
        let clamped = min(max(displayedAmplitude, 0), 1)
        return pow(clamped, 1.35)
    }

    private var ambientPulse: Double {
        pulsePhase ? 1 : 0
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppTheme.Colors.record.opacity(isActive ? 0.12 : 0.03),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .scaleEffect(backgroundScale)
                .opacity(isActive ? 0.82 + normalizedAmplitude * 0.18 : 0.45)

            ForEach(0..<ringCount, id: \.self) { index in
                Circle()
                    .stroke(
                        AppTheme.Colors.record.opacity(ringOpacity(for: index)),
                        lineWidth: ringStrokeWidth(for: index)
                    )
                    .frame(width: ringBaseSize(for: index), height: ringBaseSize(for: index))
                    .scaleEffect(ringScale(for: index))
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            AppTheme.Colors.record,
                            AppTheme.Colors.record.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 88, height: 88)
                .scaleEffect(coreScale)
                .shadow(color: AppTheme.Colors.record.opacity(coreShadowOpacity), radius: coreShadowRadius)
                .overlay(
                    Image(systemName: isActive ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                )
        }
        .animation(.easeInOut(duration: 0.45), value: isActive)
        .onAppear {
            displayedAmplitude = amplitude
            updatePulseAnimation()
        }
        .onChange(of: amplitude) { _, newValue in
            animateAmplitude(to: newValue)
        }
        .onChange(of: isActive) { _, _ in
            if !isActive {
                displayedAmplitude = 0
            }
            updatePulseAnimation()
        }
    }

    private func ringBaseSize(for index: Int) -> CGFloat {
        [136, 180, 230][index]
    }

    private var backgroundScale: Double {
        guard isActive else { return 0.8 }
        return 0.96 + ambientPulse * 0.04 + normalizedAmplitude * 0.34
    }

    private var coreScale: Double {
        guard isActive else { return 1.0 }
        return 1.0 + ambientPulse * 0.015 + normalizedAmplitude * 0.08
    }

    private var coreShadowOpacity: Double {
        isActive ? 0.3 + normalizedAmplitude * 0.34 : 0.15
    }

    private var coreShadowRadius: CGFloat {
        isActive ? 16 + normalizedAmplitude * 24 : 10
    }

    private func ringOpacity(for index: Int) -> Double {
        let base: Double = [0.42, 0.24, 0.12][index]
        let amplitudeBoost: Double = [0.14, 0.12, 0.1][index]
        let pulseBoost: Double = [0.05, 0.04, 0.03][index]
        return isActive
            ? min(0.9, base + normalizedAmplitude * amplitudeBoost + ambientPulse * pulseBoost)
            : base * 0.3
    }

    private func ringStrokeWidth(for index: Int) -> CGFloat {
        let base: CGFloat = [2.4, 1.7, 1.0][index]
        let boost: CGFloat = [1.1, 0.8, 0.5][index]
        return base + normalizedAmplitude * boost
    }

    private func ringScale(for index: Int) -> Double {
        let ambientRange: [Double] = [0.02, 0.035, 0.05]
        let reactiveRange: [Double] = [0.22, 0.38, 0.58]
        return isActive
            ? 0.98 + ambientPulse * ambientRange[index] + normalizedAmplitude * reactiveRange[index]
            : 0.92
    }

    private func animateAmplitude(to newValue: Double) {
        let clampedValue = min(max(newValue, 0), 1)
        let animation = clampedValue > displayedAmplitude
            ? Animation.spring(response: 0.18, dampingFraction: 0.72)
            : Animation.easeOut(duration: 0.24)

        withAnimation(animation) {
            displayedAmplitude = clampedValue
        }
    }

    private func updatePulseAnimation() {
        if isActive {
            pulsePhase = false
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulsePhase = true
            }
        } else {
            pulsePhase = false
        }
    }
}

// MARK: - Pulsing Recording Dot

struct PulsingDotView: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(AppTheme.Colors.record)
            .frame(width: 8, height: 8)
            .opacity(pulsing ? 0.25 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}

// MARK: - Live Transcript Overlay

struct LiveTranscriptOverlayView: View {
    let transcript: String
    let chunksReceived: Int
    let chunksTranscribed: Int
    let errorMessage: String?
    let maximumHeight: CGFloat
    let dismiss: () -> Void

    private let maximumWidth: CGFloat = 420

    private var displayTranscript: String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return "Listening for speech..."
        }

        return trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    SectionHeaderView(title: "Live Transcript")

                    Text("Review what is being captured without leaving the recorder.")
                        .font(.caption)
                        .foregroundStyle(AppTheme.Colors.textTertiary)
                }

                Spacer()

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.Colors.surfaceLight.opacity(0.72))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                statusPill(
                    title: chunksReceived > 0 ? "\(chunksTranscribed)/\(chunksReceived) ready" : "Waiting",
                    systemImage: "waveform.badge.mic"
                )

                if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    statusPill(title: "Listening", systemImage: "dot.radiowaves.left.and.right")
                }
            }

            transcriptContent

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                    Text(errorMessage)
                        .font(.caption)
                }
                .foregroundStyle(AppTheme.Colors.error)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: maximumWidth)
        .frame(maxHeight: maximumHeight, alignment: .top)
        .background(.ultraThinMaterial)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .fill(AppTheme.Colors.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl)
                .stroke(AppTheme.Colors.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl))
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
    }

    private var transcriptContent: some View {
        ViewThatFits(in: .vertical) {
            transcriptText
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                transcriptText
                    .padding(.bottom, AppTheme.Spacing.sm)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, AppTheme.Spacing.xs)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.Colors.background.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
    }

    private var transcriptText: some View {
        Text(displayTranscript)
            .font(.subheadline)
            .foregroundStyle(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AppTheme.Colors.textTertiary : AppTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private func statusPill(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(AppTheme.Colors.surfaceLight.opacity(0.68))
            .clipShape(Capsule())
    }
}

// MARK: - Recording Control Button

struct RecordingTopBarButton: View {
    let isPresented: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isPresented ? "xmark" : "quote.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))

                Text(isPresented ? "Close" : "Transcript")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(AppTheme.Colors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .fill(AppTheme.Colors.surface.opacity(0.5))
            }
            .overlay(
                Capsule()
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

struct RecordingControlButton: View {
    let icon: String
    let label: String
    let size: CGFloat
    let iconSize: CGFloat
    let foreground: Color
    let background: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(background)
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: iconSize, weight: .semibold))
                            .foregroundStyle(foreground)
                    )

                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
        }
    }
}
