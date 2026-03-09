import AppKit
import SwiftUI

@MainActor
private enum RuntimeRetainer {
    static var state: AppState?
    static var permissionCenter: PermissionCenter?
    static var misspellingDictionary: MisspellingDictionary?
    static var mainWindowController: MainWindowController?
    static var updaterController: UpdaterController?
    static var overlayController: OverlayController?
    static var hotkeyManager: HotkeyManager?
    static var listeningAudioCoordinator: ListeningAudioCoordinator?
    static var whisperTestFlowCoordinator: WhisperTestFlowCoordinator?
    static var whisperEngine: WhisperEngine?
}

public struct TwoRelayCoreScene: Scene {
    @StateObject private var state: AppState
    @StateObject private var permissionCenter: PermissionCenter
    @StateObject private var misspellingDictionary: MisspellingDictionary
    @StateObject private var mainWindowController: MainWindowController
    @StateObject private var updaterController: UpdaterController
    @StateObject private var overlayController: OverlayController
    @StateObject private var hotkeyManager: HotkeyManager
    private let listeningAudioCoordinator: ListeningAudioCoordinator
    private let whisperTestFlowCoordinator: WhisperTestFlowCoordinator
    private let whisperEngine: WhisperEngine

    public init() {
        let state = AppState()
        _state = StateObject(wrappedValue: state)
        RuntimeRetainer.state = state
        let permissionCenter = PermissionCenter()
        _permissionCenter = StateObject(wrappedValue: permissionCenter)
        RuntimeRetainer.permissionCenter = permissionCenter

        let misspellingDictionary = MisspellingDictionary()
        _misspellingDictionary = StateObject(wrappedValue: misspellingDictionary)
        RuntimeRetainer.misspellingDictionary = misspellingDictionary
        let mainWindowController = MainWindowController()
        _mainWindowController = StateObject(wrappedValue: mainWindowController)
        RuntimeRetainer.mainWindowController = mainWindowController
        let updaterController = UpdaterController()
        _updaterController = StateObject(wrappedValue: updaterController)
        RuntimeRetainer.updaterController = updaterController
        let updateCheckAction = {
            if updaterController.canCheckForUpdates {
                updaterController.checkForUpdates()
            } else {
                state.reportStatus(
                    updaterController.configurationErrorMessage ?? "Updates are currently unavailable.",
                    level: .warning
                )
            }
        }

        let targetDispatcher = TargetDispatcher(permissionCenter: permissionCenter)
        let whisperEngine = WhisperEngine(modelPath: state.modelPath)
        self.whisperEngine = whisperEngine
        RuntimeRetainer.whisperEngine = whisperEngine
        let listeningAudioCoordinator = ListeningAudioCoordinator(
            appState: state,
            permissionCenter: permissionCenter,
            misspellingDictionary: misspellingDictionary,
            whisperEngine: whisperEngine,
            targetDispatcher: targetDispatcher
        )
        self.listeningAudioCoordinator = listeningAudioCoordinator
        RuntimeRetainer.listeningAudioCoordinator = listeningAudioCoordinator

        let overlayController = OverlayController(
            state: state,
            onSend: {
                listeningAudioCoordinator.sendReadyPromptToTarget()
            },
            onCopy: {
                listeningAudioCoordinator.copyReadyPromptToClipboard()
            },
            onCancel: {
                listeningAudioCoordinator.cancelReadyPrompt()
            }
        )
        _overlayController = StateObject(wrappedValue: overlayController)
        RuntimeRetainer.overlayController = overlayController

        let hotkeyManager = HotkeyManager(appState: state)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)
        RuntimeRetainer.hotkeyManager = hotkeyManager
        let whisperTestFlowCoordinator = WhisperTestFlowCoordinator(
            appState: state,
            misspellingDictionary: misspellingDictionary,
            whisperEngine: whisperEngine
        )
        self.whisperTestFlowCoordinator = whisperTestFlowCoordinator
        RuntimeRetainer.whisperTestFlowCoordinator = whisperTestFlowCoordinator

        DispatchQueue.main.async {
            AppBranding.applyDockIcon()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Task { @MainActor in
                mainWindowController.present(
                    state: state,
                    permissionCenter: permissionCenter,
                    misspellingDictionary: misspellingDictionary,
                    onRunWhisperTestFlow: {
                        whisperTestFlowCoordinator.runRecordThreeSecondsThenTranslateToEnglish()
                    },
                    onOpenSettings: {
                        permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
                        state.isSettingsPanelPresented = true
                    },
                    onOpenHelp: {
                        Self.openHelpProfile()
                    },
                    canCheckForUpdates: updaterController.canCheckForUpdates,
                    updatesDisabledReason: updaterController.configurationErrorMessage,
                    onCheckForUpdates: updateCheckAction
                )
            }
        }
    }

    public var body: some Scene {
        // Ensure side-effect coordinators are initialized for hotkey and overlay behavior.
        let _ = hotkeyManager
        let _ = overlayController

        MenuBarExtra("2relay", systemImage: "waveform") {
            MenuBarView(
                state: state,
                canCheckForUpdates: updaterController.canCheckForUpdates,
                onOpenMain: {
                    mainWindowController.present(
                        state: state,
                        permissionCenter: permissionCenter,
                        misspellingDictionary: misspellingDictionary,
                        onRunWhisperTestFlow: {
                            whisperTestFlowCoordinator.runRecordThreeSecondsThenTranslateToEnglish()
                        },
                        onOpenSettings: {
                            permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
                            state.isSettingsPanelPresented = true
                        },
                        onOpenHelp: {
                            Self.openHelpProfile()
                        },
                        canCheckForUpdates: updaterController.canCheckForUpdates,
                        updatesDisabledReason: updaterController.configurationErrorMessage,
                        onCheckForUpdates: {
                            handleCheckForUpdates()
                        }
                    )
                },
                onCheckForUpdates: {
                    handleCheckForUpdates()
                },
                onOpenSettings: {
                    permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
                    state.isSettingsPanelPresented = true
                    mainWindowController.present(
                        state: state,
                        permissionCenter: permissionCenter,
                        misspellingDictionary: misspellingDictionary,
                        onRunWhisperTestFlow: {
                            whisperTestFlowCoordinator.runRecordThreeSecondsThenTranslateToEnglish()
                        },
                        onOpenSettings: {
                            permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
                            state.isSettingsPanelPresented = true
                        },
                        onOpenHelp: {
                            Self.openHelpProfile()
                        },
                        canCheckForUpdates: updaterController.canCheckForUpdates,
                        updatesDisabledReason: updaterController.configurationErrorMessage,
                        onCheckForUpdates: {
                            handleCheckForUpdates()
                        }
                    )
                }
            )
        }
        .menuBarExtraStyle(.menu)
    }

    private static func openHelpProfile() {
        guard let url = URL(string: "https://x.com/mes28io") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func handleCheckForUpdates() {
        if updaterController.canCheckForUpdates {
            updaterController.checkForUpdates()
        } else {
            state.reportStatus(
                updaterController.configurationErrorMessage ?? "Updates are currently unavailable.",
                level: .warning
            )
        }
    }
}

public struct TwoRelayCoreApp: App {
    public init() {}

    public var body: some Scene {
        TwoRelayCoreScene()
    }
}
