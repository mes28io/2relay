import KeyboardShortcuts
import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case personalize
    case shortcut
    case workflow
    case permissions

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .personalize:
            return "Personalize"
        case .shortcut:
            return "Shortcut"
        case .workflow:
            return "How It Works"
        case .permissions:
            return "Permissions"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            return "Set up 2relay in under a minute."
        case .personalize:
            return "Pick your defaults for relay behavior."
        case .shortcut:
            return "Choose your push-to-talk hotkey."
        case .workflow:
            return "Learn the quick voice-to-prompt flow."
        case .permissions:
            return "Grant required access for recording and auto-paste."
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var state: AppState
    @ObservedObject var permissionCenter: PermissionCenter
    let onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @State private var hotkeyPreview = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            stepBody
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(windowSurfaceColor)
        .onAppear {
            permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
            hotkeyPreview = currentHotkeyDisplayText
        }
        .onChange(of: currentStep) { step in
            if step == .permissions {
                permissionCenter.refreshFromSystemAndRedirectUnrecognizedIfNeeded()
            }
        }
        .task(id: currentStep) {
            guard currentStep == .permissions else {
                return
            }

            while !Task.isCancelled {
                permissionCenter.refreshFromSystem()
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let logo = AppBranding.loadLogoImage() {
                    Image(nsImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(mainTextColor)
                }

                Text("2relay Setup")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(mainTextColor)

                Spacer()

                Text("Step \(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(mainTextColor.opacity(0.08), in: Capsule())
            }

            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases) { step in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(step.rawValue <= currentStep.rawValue ? accentColor : mainTextColor.opacity(0.18))
                        .frame(height: 6)
                }
            }
        }
        .padding(18)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var stepBody: some View {
        Group {
            switch currentStep {
            case .welcome:
                welcomeStep
            case .personalize:
                personalizeStep
            case .shortcut:
                shortcutStep
            case .workflow:
                workflowStep
            case .permissions:
                permissionsStep
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .transition(.opacity)
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Talk naturally in any language, get clean English prompts instantly.")
                .font(.system(size: 34, weight: .medium, design: .serif))
                .foregroundStyle(mainTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("This onboarding will personalize your defaults and show the exact relay flow from hotkey to prompt output.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(secondaryTextColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                onboardingFeatureRow(
                    icon: "mic.fill",
                    title: "Hold your hotkey and speak",
                    description: "Push-to-talk capture starts on key down and ends on key up."
                )
                onboardingFeatureRow(
                    icon: "text.bubble.fill",
                    title: "Auto-translate and clean",
                    description: "Whisper translates to English, then 2relay extracts the Goal line."
                )
                onboardingFeatureRow(
                    icon: "paperplane.fill",
                    title: "Paste where you work",
                    description: "Send to Claude Code, Codex, or clipboard for any app."
                )
            }
            .padding(14)
            .background(mainTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)
        }
        .padding(22)
        .background(promotionalCardBackgroundColor, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(mainTextColor.opacity(0.1), lineWidth: 1)
        )
    }

    private var personalizeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitleCard(title: currentStep.title, subtitle: currentStep.subtitle)

            VStack(alignment: .leading, spacing: 10) {
                Text("Default target")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)

                Picker("Default target", selection: $state.defaultTarget) {
                    ForEach(TargetApp.allCases) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if state.defaultTarget == .claudeCode {
                    Text("Claude Code mode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                        .padding(.top, 2)

                    Picker("Claude Code mode", selection: $state.claudeCodeMode) {
                        ForEach(ClaudeCodeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
            }
            .padding(14)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Input style")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)

                Picker("Hotkey mode", selection: $state.hotkeyMode) {
                    ForEach(AppState.HotkeyMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Text("Behavior")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
                    .padding(.top, 2)

                HStack(spacing: 10) {
                    Text("Clean prompt output")
                    Spacer()
                    Toggle("", isOn: $state.cleanPromptEnabled)
                        .labelsHidden()
                }
                .font(.system(size: 13, weight: .medium))

                HStack(spacing: 10) {
                    Text("Auto-send after transcription")
                    Spacer()
                    Toggle("", isOn: $state.autoSendAfterTranscriptionEnabled)
                        .labelsHidden()
                }
                .font(.system(size: 13, weight: .medium))
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)
        }
    }

    private var workflowStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitleCard(title: currentStep.title, subtitle: currentStep.subtitle)

            VStack(spacing: 10) {
                workflowRow(number: 1, title: "Hold hotkey", detail: "Recording starts immediately.")
                workflowRow(number: 2, title: "Release hotkey", detail: "Recording stops and transcribing begins.")
                workflowRow(number: 3, title: "Whisper translate", detail: "Audio is translated to English locally.")
                workflowRow(number: 4, title: "Goal extraction", detail: "2relay keeps the goal line as final relay content.")
                workflowRow(number: 5, title: "Copy or auto-send", detail: "Prompt is copied and pasted to your selected target.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Output your users will see")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)

                Text("- Build a login page with email/password and a remember-me checkbox.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(mainTextColor)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(mainTextColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(14)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)
        }
    }

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitleCard(title: currentStep.title, subtitle: currentStep.subtitle)

            VStack(alignment: .leading, spacing: 10) {
                Text("Set your relay hotkey")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)

                Text("Tap the field, then press your preferred keys.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(secondaryTextColor)

                HotkeyRecorderField(name: .relayListen) { shortcut in
                    hotkeyPreview = shortcut?.description ?? "None"
                    state.reportStatus("Hotkey updated: \(hotkeyPreview)", level: .success)
                }
                .frame(height: 30)

                HStack(spacing: 8) {
                    Text("Current:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                    Text(hotkeyPreview)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mainTextColor)
                }

                Button("Continue with default (Control + Space)") {
                    KeyboardShortcuts.setShortcut(RelayHotkeyDefaults.preferred, for: .relayListen)
                    hotkeyPreview = currentHotkeyDisplayText
                    state.reportStatus("Hotkey updated: \(hotkeyPreview)", level: .success)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isUsingDefaultHotkey)
            }
            .padding(14)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Spacer(minLength: 0)
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitleCard(title: currentStep.title, subtitle: currentStep.subtitle)

            VStack(alignment: .leading, spacing: 10) {
                permissionRow(
                    title: "Microphone",
                    state: permissionCenter.microphoneState,
                    detail: permissionCenter.detailText(for: .microphone),
                    allowButtonTitle: "Allow Access",
                    onAllowAccess: {
                        if !permissionCenter.isInstalledInApplications {
                            permissionCenter.revealInstallLocationsInFinder()
                            state.reportStatus(
                                "Move 2relay.app to Applications, relaunch it from Applications, then allow microphone access.",
                                level: .warning
                            )
                        }

                        permissionCenter.refreshFromSystem()
                        Task {
                            await permissionCenter.requestMicrophonePermissionIfNeeded()
                            permissionCenter.refreshFromSystem()

                            if permissionCenter.microphoneState != .granted {
                                openSystemSettings(for: .microphone)
                                state.reportStatus("Enable microphone access for 2relay in System Settings.", level: .warning)
                            }
                        }
                    },
                    onOpenSettings: {
                        openSystemSettings(for: .microphone)
                    }
                )

                permissionRow(
                    title: "Accessibility",
                    state: permissionCenter.accessibilityState,
                    detail: permissionCenter.detailText(for: .accessibility),
                    allowButtonTitle: "Allow Access",
                    onAllowAccess: {
                        permissionCenter.requestAccessibilityPromptIfNeeded(force: true)
                        permissionCenter.refreshFromSystem()
                        if permissionCenter.accessibilityState != .granted {
                            openSystemSettings(for: .accessibility)
                        }
                    },
                    onOpenSettings: {
                        openSystemSettings(for: .accessibility)
                    }
                )
            }
            .padding(14)
            .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Text("Tip: Accessibility is required for automatic Cmd+V paste.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryTextColor)

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Button("Back") {
                withAnimation(.easeInOut(duration: 0.14)) {
                    goToPreviousStep()
                }
            }
            .buttonStyle(.bordered)
            .disabled(currentStep == .welcome)

            Spacer()

            Text(currentStep.subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryTextColor)

            Spacer()

            Button(nextButtonTitle) {
                withAnimation(.easeInOut(duration: 0.14)) {
                    handleNextAction()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func onboardingFeatureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mainTextColor)
                Text(description)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
            }
        }
    }

    private func stepTitleCard(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(mainTextColor)
            Text(subtitle)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func workflowRow(number: Int, title: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mainTextColor)
                Text(detail)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func permissionRow(
        title: String,
        state: PermissionState,
        detail: String,
        allowButtonTitle: String,
        onAllowAccess: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(mainTextColor)

                Spacer(minLength: 0)

                Text(state.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(permissionColor(for: state).opacity(0.18), in: Capsule())
                    .foregroundStyle(permissionColor(for: state))
            }

            Text(detail)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(allowButtonTitle) {
                    onAllowAccess()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(state == .granted)

                Button("Open Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(mainTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func openSystemSettings(for kind: PermissionKind) {
        guard permissionCenter.openSystemSettings(for: kind) else {
            state.reportStatus(
                "Could not open System Settings automatically. Open Privacy & Security > \(kind.displayName).",
                level: .warning
            )
            return
        }
    }

    private var nextButtonTitle: String {
        if currentStep == .permissions {
            return "Finish Setup"
        }

        return "Continue"
    }

    private func handleNextAction() {
        if currentStep == .permissions {
            state.completeOnboarding()
            onComplete()
            return
        }

        goToNextStep()
    }

    private func goToNextStep() {
        guard let step = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        currentStep = step
    }

    private func goToPreviousStep() {
        guard let step = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = step
    }

    private var currentHotkeyDisplayText: String {
        KeyboardShortcuts.getShortcut(for: .relayListen)?.description ?? "None"
    }

    private var isUsingDefaultHotkey: Bool {
        KeyboardShortcuts.getShortcut(for: .relayListen) == RelayHotkeyDefaults.preferred
    }

    private var accentColor: Color {
        Color(red: 45 / 255, green: 120 / 255, blue: 235 / 255)
    }

    private var windowSurfaceColor: Color {
        Color(red: 250 / 255, green: 248 / 255, blue: 242 / 255)
    }

    private var cardBackgroundColor: Color {
        Color(red: 245 / 255, green: 242 / 255, blue: 234 / 255)
    }

    private var promotionalCardBackgroundColor: Color {
        Color(red: 238 / 255, green: 236 / 255, blue: 216 / 255)
    }

    private var mainTextColor: Color {
        Color(red: 79 / 255, green: 78 / 255, blue: 78 / 255)
    }

    private var secondaryTextColor: Color {
        mainTextColor.opacity(0.72)
    }
}
