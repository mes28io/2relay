import AppKit
import Combine
import SwiftUI

private final class NotchOverlayPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

@MainActor
final class OverlayController: ObservableObject {
    private let state: AppState
    private let onSend: () -> Void
    private let onCopy: () -> Void
    private let onCancel: () -> Void

    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private var screenObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var isHiding = false

    init(
        state: AppState,
        onSend: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.state = state
        self.onSend = onSend
        self.onCopy = onCopy
        self.onCancel = onCancel

        state.$overlayState
            .removeDuplicates()
            .sink { [weak self] overlayState in
                guard let self else {
                    return
                }

                if overlayState == .idle {
                    hide(immediately: true)
                } else {
                    show(for: overlayState)
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show(for overlayState: AppState.OverlayState) {
        if panel == nil {
            makePanel()
        }

        let targetFrame = frame(for: size(for: overlayState))

        guard let panel else {
            return
        }

        if isHiding {
            panel.animator().alphaValue = 1
            isHiding = false
        }

        if !isVisible {
            let startFrame = growStartFrame(for: targetFrame)
            panel.alphaValue = 0
            panel.setFrame(startFrame, display: true)
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        }

        isVisible = true
    }

    func hide(immediately: Bool) {
        guard let panel else {
            return
        }

        if immediately || !isVisible {
            panel.orderOut(nil)
            panel.alphaValue = 1
            isVisible = false
            isHiding = false
            return
        }

        isHiding = true
        let currentFrame = panel.frame
        var hiddenFrame = currentFrame
        hiddenFrame.origin.y += 10

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }
                guard self.isHiding else {
                    return
                }
                panel.orderOut(nil)
                panel.alphaValue = 1
                self.isVisible = false
                self.isHiding = false
            }
        }
    }

    private func makePanel() {
        let panel = NotchOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 468, height: 94),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true

        panel.contentView = NSHostingView(
            rootView: OverlayView(
                state: state,
                onSend: onSend,
                onCopy: onCopy,
                onCancel: onCancel
            )
        )
        self.panel = panel

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updatePositionForCurrentState(animated: false)
            }
        }
    }

    private func updatePositionForCurrentState(animated: Bool) {
        let target = state.overlayState == .idle ? .listening : state.overlayState
        setFrame(for: target, animated: animated)
    }

    private func setFrame(for overlayState: AppState.OverlayState, animated: Bool) {
        guard let panel else {
            return
        }

        let targetFrame = frame(for: size(for: overlayState))

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func frame(for size: NSSize) -> NSRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
        guard let screenFrame = screen?.frame else {
            return NSRect(origin: .zero, size: size)
        }
        let visibleFrameTop = screen?.visibleFrame.maxY ?? screenFrame.maxY
        let menuBarInset = max(0, screenFrame.maxY - visibleFrameTop)
        let notchOverlap = min(max(18, menuBarInset * 0.95), size.height * 0.5)

        return NSRect(
            x: screenFrame.midX - (size.width / 2),
            y: screenFrame.maxY - size.height + notchOverlap,
            width: size.width,
            height: size.height
        )
    }

    private func growStartFrame(for targetFrame: NSRect) -> NSRect {
        let startWidth = max(240, targetFrame.width * 0.78)
        let startHeight = max(50, targetFrame.height * 0.74)

        return NSRect(
            x: targetFrame.midX - (startWidth / 2),
            y: targetFrame.maxY - startHeight,
            width: startWidth,
            height: startHeight
        )
    }

    private func size(for overlayState: AppState.OverlayState) -> NSSize {
        let width = width(for: overlayState)
        switch overlayState {
        case .idle, .listening:
            return NSSize(width: width, height: 102)
        case .transcribing:
            return NSSize(width: width, height: 104)
        case .readyToSend:
            return NSSize(width: width, height: 214)
        case .error:
            return NSSize(width: width, height: 130)
        }
    }

    private func width(for overlayState: AppState.OverlayState) -> CGFloat {
        let contentText: String
        switch overlayState {
        case .idle:
            contentText = "Hold the hotkey to talk"
        case .listening:
            contentText = "Listening... release hotkey to transcribe"
        case .transcribing:
            contentText = "Transcribing and translating to English..."
        case .readyToSend:
            contentText = state.promptPreview.isEmpty ? "Ready to send" : state.promptPreview
        case .error:
            contentText = state.overlayErrorMessage ?? "Unknown error"
        }

        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let measured = (contentText as NSString).size(withAttributes: [.font: font]).width
        let chromePadding: CGFloat = overlayState == .readyToSend ? 230 : 150
        let proposed = ceil(measured + chromePadding)
        let minWidth: CGFloat = overlayState == .readyToSend ? 500 : 320
        let maxWidth: CGFloat = overlayState == .readyToSend ? 760 : 560
        return min(max(proposed, minWidth), maxWidth)
    }
}
