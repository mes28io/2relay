import SwiftUI

struct OverlayView: View {
    @ObservedObject var state: AppState

    let onSend: () -> Void
    let onCopy: () -> Void
    let onCancel: () -> Void

    @State private var shouldPulse = false

    var body: some View {
        VStack(spacing: layout.contentSpacing) {
            header

            content
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                    )
                )
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.top, layout.verticalPadding + layout.notchClearance)
        .padding(.bottom, layout.verticalPadding)
        .frame(maxWidth: .infinity, minHeight: layout.minHeight, alignment: .top)
        .background(
            TopDockedNotchShape(bottomRadius: layout.bottomCornerRadius)
                .fill(Color.black.opacity(0.98))
        )
        .overlay(
            TopDockedNotchShape(bottomRadius: layout.bottomCornerRadius)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .compositingGroup()
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: state.overlayState)
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: state.defaultTarget)
        .onAppear {
            shouldPulse = true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .opacity(state.overlayState == .listening && shouldPulse ? 0.35 : 1.0)
                .animation(
                    state.overlayState == .listening
                        ? .easeInOut(duration: 0.7).repeatForever(autoreverses: true)
                        : .easeOut(duration: 0.15),
                    value: shouldPulse
                )

            Text(state.overlayState.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)

            Spacer()

            targetChip
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.overlayState {
        case .idle:
            EmptyView()

        case .listening:
            HStack(spacing: 10) {
                OverlayWaveformView(color: .red.opacity(0.9))
                    .frame(width: 48, height: 18)

                Text("Listening... release hotkey to transcribe")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .transcribing:
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                    .tint(.orange)

                Text("Transcribing and translating to English...")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .readyToSend:
            VStack(alignment: .leading, spacing: 8) {
                Text(state.promptPreview)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button("Send") {
                        onSend()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Copy") {
                        onCopy()
                    }
                    .buttonStyle(.bordered)

                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                }
            }

        case .error:
            Text(state.overlayErrorMessage ?? "Unknown error")
                .font(.caption)
                .foregroundStyle(.red.opacity(0.9))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var targetChip: some View {
        Text(state.defaultTarget.displayName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.95))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private var layout: Layout {
        switch state.overlayState {
        case .idle, .listening:
            return Layout(bottomCornerRadius: 28, minHeight: 102, horizontalPadding: 16, verticalPadding: 12, contentSpacing: 8, notchClearance: 18)
        case .transcribing:
            return Layout(bottomCornerRadius: 28, minHeight: 104, horizontalPadding: 16, verticalPadding: 12, contentSpacing: 8, notchClearance: 18)
        case .readyToSend:
            return Layout(bottomCornerRadius: 24, minHeight: 206, horizontalPadding: 16, verticalPadding: 12, contentSpacing: 10, notchClearance: 18)
        case .error:
            return Layout(bottomCornerRadius: 24, minHeight: 126, horizontalPadding: 16, verticalPadding: 12, contentSpacing: 8, notchClearance: 18)
        }
    }

    private var statusColor: Color {
        switch state.overlayState {
        case .idle:
            return .gray
        case .listening:
            return .red
        case .transcribing:
            return .orange
        case .readyToSend:
            return .green
        case .error:
            return .pink
        }
    }

    private struct Layout {
        let bottomCornerRadius: CGFloat
        let minHeight: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let contentSpacing: CGFloat
        let notchClearance: CGFloat
    }
}

private struct TopDockedNotchShape: Shape {
    let bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.width / 2, rect.height)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()

        return path
    }
}

private struct OverlayWaveformView: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.06, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = t * 5.4 + (Double(index) * 0.8)
                    let height = 6 + CGFloat((sin(phase) + 1) * 5.5)
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: 4, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}
