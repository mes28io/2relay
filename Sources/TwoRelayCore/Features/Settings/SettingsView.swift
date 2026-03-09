import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var permissionCenter: PermissionCenter
    var canCheckForUpdates: Bool = false
    var updatesDisabledReason: String? = nil
    var onCheckForUpdates: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Send Target")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    Text("2relay now pastes into the currently focused app only.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(mainTextColor)
                }
            }

            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Behavior")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)

                    trailingToggleRow("Clean prompt", isOn: $state.cleanPromptEnabled)
                    trailingToggleRow("Auto-copy prompt clip to clipboard", isOn: $state.autoCopyPromptToClipboardEnabled)
                    trailingToggleRow("Auto-send prompt after transcription", isOn: $state.autoSendAfterTranscriptionEnabled)
                }
                .toggleStyle(.switch)
            }

            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Updates")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                        Spacer()
                        Button("Check Now") {
                            onCheckForUpdates?()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(!canCheckForUpdates || onCheckForUpdates == nil)
                    }

                    Text("2relay can check GitHub-hosted release updates automatically when a release build includes a valid Sparkle feed.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(mainTextColor)

                    Text(canCheckForUpdates ? "Automatic update checks are enabled for this build." : (updatesDisabledReason ?? "Updates are not available in this build yet."))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondaryTextColor)
                }
            }

            sectionCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Permissions")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                        Spacer()
                        Button("Refresh") {
                            permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
                        }
                    }

                    permissionRow(kind: .microphone, state: permissionCenter.microphoneState)
                    permissionRow(kind: .accessibility, state: permissionCenter.accessibilityState)

                    HStack(spacing: 8) {
                        Button("Allow Microphone Access") {
                            handleMicrophoneAccessAction()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(permissionCenter.microphoneState == .granted)

                        Button("Allow Accessibility Access") {
                            permissionCenter.requestAccessibilityPromptIfNeeded(force: true)
                            permissionCenter.refreshFromSystem()
                            if permissionCenter.accessibilityState != .granted {
                                openSystemSettings(for: .accessibility)
                            }
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                }
            }

            Text("Accessibility is required for auto-paste (Cmd+V).")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 500)
        .background(appBackgroundColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(mainTextColor.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
        }
        .task {
            while !Task.isCancelled {
                permissionCenter.refreshFromSystem()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            if let logo = AppBranding.loadLogoImage() {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(mainTextColor)
            }

            Text("Settings")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(mainTextColor)

            Spacer(minLength: 10)

            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(mainTextColor.opacity(0.08), in: Circle())
                        .foregroundStyle(mainTextColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trailingToggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(mainTextColor)

            Spacer(minLength: 0)

            Toggle("", isOn: isOn)
                .labelsHidden()
        }
    }

    private func handleMicrophoneAccessAction() {
        if !permissionCenter.isInstalledInApplications {
            permissionCenter.revealInstallLocationsInFinder()
            state.reportStatus(
                "Move 2relay.app to Applications, relaunch it from Applications, then allow microphone access.",
                level: .warning
            )
        }

        permissionCenter.refreshFromSystem()
        guard permissionCenter.microphoneState != .granted else {
            permissionCenter.refreshFromSystem()
            return
        }

        Task {
            await permissionCenter.requestMicrophonePermissionIfNeeded()
            permissionCenter.refreshFromSystem()

            if permissionCenter.microphoneState != .granted {
                openSystemSettings(for: .microphone)
                state.reportStatus("Enable microphone access for 2relay in System Settings.", level: .warning)
            }
        }
    }

    private func openSystemSettings(for kind: PermissionKind) {
        guard !permissionCenter.openSystemSettings(for: kind) else {
            return
        }

        state.reportStatus(
            "Could not open System Settings automatically. Open Privacy & Security > \(kind.displayName).",
            level: .warning
        )
    }

    private func permissionRow(kind: PermissionKind, state: PermissionState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(kind.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(mainTextColor)

                Spacer()

                Text(state.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(permissionColor(for: state).opacity(0.18), in: Capsule())
                    .foregroundStyle(permissionColor(for: state))

                Button("Open in Settings") {
                    openSystemSettings(for: kind)
                }
                .font(.system(size: 11, weight: .semibold))
            }

            Text(permissionCenter.detailText(for: kind))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private func permissionColor(for state: PermissionState) -> Color {
        switch state {
        case .unknown:
            return .secondary
        case .granted:
            return .green
        case .denied:
            return .orange
        case .restricted:
            return .red
        case .unrecognized:
            return .purple
        }
    }

    private var appBackgroundColor: Color {
        Color(red: 250 / 255, green: 248 / 255, blue: 242 / 255)
    }

    private var cardBackgroundColor: Color {
        Color(red: 245 / 255, green: 242 / 255, blue: 234 / 255)
    }

    private var mainTextColor: Color {
        Color(red: 79 / 255, green: 78 / 255, blue: 78 / 255)
    }

    private var secondaryTextColor: Color {
        mainTextColor.opacity(0.72)
    }
}
