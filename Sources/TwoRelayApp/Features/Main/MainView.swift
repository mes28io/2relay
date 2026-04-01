import AppKit
import KeyboardShortcuts
import SwiftUI

private enum SidebarTab: String, CaseIterable, Identifiable {
    case home
    case dictionary
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:
            return "Home"
        case .dictionary:
            return "Dictionary"
        case .shortcuts:
            return "Shortcuts"
        }
    }

    var iconName: String {
        switch self {
        case .home:
            return "square.grid.2x2"
        case .dictionary:
            return "brain.head.profile.fill"
        case .shortcuts:
            return "command.square"
        }
    }
}

struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var permissionCenter: PermissionCenter
    @ObservedObject var misspellingDictionary: MisspellingDictionary
    @ObservedObject var layoutState: MainLayoutState

    @ObservedObject var updaterController: UpdaterController

    let onRunWhisperTestFlow: () -> Void
    let onOpenSettings: () -> Void
    let onOpenHelp: () -> Void

    @State private var selectedTab: SidebarTab = .home
    @State private var hoveredSidebarItemID: String?
    @State private var sidebarItemFrames: [String: CGRect] = [:]
    @State private var dictionarySourceInput = ""
    @State private var dictionaryReplacementInput = ""

    var body: some View {
        ZStack {
            rootContent
            .frame(minWidth: 1100, minHeight: 800)
            .background(windowSurfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(mainTextColor.opacity(0.06), lineWidth: 1)
            )
            .padding(8)

            if state.hasCompletedOnboarding, state.isSettingsPanelPresented {
                settingsPanelOverlay
                    .transition(.opacity)
                    .zIndex(2)
            }

            if state.hasCompletedOnboarding, layoutState.isSidebarCollapsed {
                collapsedSidebarTooltipOverlay
                    .zIndex(3)
            }
        }
        .coordinateSpace(name: "MainViewCoordinateSpace")
        .onPreferenceChange(SidebarItemFramePreferenceKey.self) { value in
            sidebarItemFrames = value
        }
        .animation(.easeInOut(duration: 0.16), value: state.isSettingsPanelPresented)
        .task {
            await state.licenseValidator.refreshTokenIfNeeded()
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if state.hasCompletedOnboarding {
            HStack(spacing: 0) {
                sidebar

                Group {
                    switch selectedTab {
                    case .home:
                        homeContent
                    case .dictionary:
                        dictionaryContent
                    case .shortcuts:
                        shortcutsContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 12)
                .padding(.trailing, 12)
            }
        } else {
            OnboardingView(
                state: state,
                permissionCenter: permissionCenter,
                licenseValidator: state.licenseValidator,
                onComplete: {
                    selectedTab = .home
                }
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            sidebarBrandHeader
                .padding(.bottom, 6)

            ForEach(SidebarTab.allCases) { tab in
                let rowID = "tab-\(tab.rawValue)"
                Button {
                    selectedTab = tab
                } label: {
                    sidebarRowContent(
                        iconName: tab.iconName,
                        title: tab.title,
                        showsText: !layoutState.isSidebarCollapsed
                    )
                    .background {
                        if selectedTab == tab || hoveredSidebarItemID == rowID {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(mainTextColor.opacity(selectedTab == tab ? 0.12 : 0.08))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tabTooltipText(for: tab))
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SidebarItemFramePreferenceKey.self,
                            value: [rowID: proxy.frame(in: .named("MainViewCoordinateSpace"))]
                        )
                    }
                )
                .onHover { hovering in
                    if hovering {
                        hoveredSidebarItemID = rowID
                    } else if hoveredSidebarItemID == rowID {
                        hoveredSidebarItemID = nil
                    }
                }
                .pointingHandCursorOnHover()
            }

            Spacer(minLength: 22)

            Button {
                onOpenSettings()
            } label: {
                let rowID = "action-settings"
                sidebarActionLabel(
                    title: "Settings",
                    iconName: "gearshape",
                    rowID: rowID
                )
            }
            .buttonStyle(.plain)
            .help("Settings: target, behavior, permissions")
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SidebarItemFramePreferenceKey.self,
                        value: ["action-settings": proxy.frame(in: .named("MainViewCoordinateSpace"))]
                    )
                }
            )
            .onHover { hovering in
                if hovering {
                    hoveredSidebarItemID = "action-settings"
                } else if hoveredSidebarItemID == "action-settings" {
                    hoveredSidebarItemID = nil
                }
            }
            .pointingHandCursorOnHover()

            Button {
                onOpenHelp()
            } label: {
                let rowID = "action-help"
                sidebarActionLabel(
                    title: "Help",
                    iconName: "questionmark.circle",
                    rowID: rowID
                )
            }
            .buttonStyle(.plain)
            .help("ask me on x - @mes28io")
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SidebarItemFramePreferenceKey.self,
                        value: ["action-help": proxy.frame(in: .named("MainViewCoordinateSpace"))]
                    )
                }
            )
            .onHover { hovering in
                if hovering {
                    hoveredSidebarItemID = "action-help"
                } else if hoveredSidebarItemID == "action-help" {
                    hoveredSidebarItemID = nil
                }
            }
            .pointingHandCursorOnHover()
        }
        .padding(12)
        .frame(
            minWidth: layoutState.isSidebarCollapsed ? 78 : 230,
            maxWidth: layoutState.isSidebarCollapsed ? 78 : 230,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(sidebarContainerColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(mainTextColor.opacity(0.07), lineWidth: 1)
        )
        .padding(.vertical, 12)
        .padding(.leading, 10)
        .padding(.trailing, 6)
    }

    private var sidebarBrandHeader: some View {
        HStack(spacing: 0) {
            sidebarBrandIcon
                .frame(width: 26, alignment: .leading)

            if !layoutState.isSidebarCollapsed {
                Text("2relay")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(mainTextColor)
                    .padding(.leading, 10)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 44)
        .padding(.horizontal, 12)
        .help("2relay")
    }

    private var settingsPanelOverlay: some View {
        ZStack {
            Color.black.opacity(0.10)
                .ignoresSafeArea()
                .onTapGesture {
                    closeSettingsPanel()
                }

            SettingsView(
                state: state,
                permissionCenter: permissionCenter,
                updaterController: updaterController,
                onClose: {
                    closeSettingsPanel()
                }
            )
            .onTapGesture {
                // Intentionally swallow tap to avoid closing when interacting inside the card.
            }
        }
    }

    private var collapsedSidebarTooltipOverlay: some View {
        GeometryReader { proxy in
            if let rowID = hoveredSidebarItemID,
               let frame = sidebarItemFrames[rowID] {
                let tooltipText = sidebarTooltipText(for: rowID)
                let halfWidth = tooltipHalfWidth(for: tooltipText)
                let desiredLeftEdge = frame.maxX + 12

                Text(tooltipText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 12) // 10 + 2px requested left inset
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .position(
                        x: min(
                            max(halfWidth + 8, desiredLeftEdge + halfWidth),
                            proxy.size.width - (halfWidth + 8)
                        ),
                        y: min(max(16, frame.midY), proxy.size.height - 16)
                    )
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.linear(duration: 0.05), value: hoveredSidebarItemID)
    }

    @ViewBuilder
    private var sidebarBrandIcon: some View {
        if let logo = AppBranding.loadLogoImage() {
            Image(nsImage: logo)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(mainTextColor)
        }
    }

    private var homeContent: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    relayStatusCard
                    homePromoCard
                    latestRelaysCard
                }
                .padding(18)
                .padding(.bottom, 44)
                .foregroundStyle(mainTextColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                if updaterController.updateAvailable, let version = updaterController.latestVersionString {
                    Button("Download \(version)") {
                        updaterController.openDownload()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold))
                } else {
                    Button("Check for Updates...") {
                        Task { await updaterController.checkForUpdates() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .semibold))
                    .disabled(updaterController.isChecking)
                }
            }
            .padding(.leading, 22)
            .padding(.bottom, 18)
        }
    }

    private var relayStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Status")
                    .font(.title3.weight(.medium))

                Spacer()

                Text(state.statusTimestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(color(for: state.statusLevel))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                Text(state.statusMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(mainTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.statusHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(state.statusHistory.prefix(4))) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(color(for: entry.level))
                                .frame(width: 6, height: 6)
                                .padding(.top, 5)

                            Text(entry.message)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(secondaryTextColor.opacity(0.92))
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var latestRelaysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Latest Relays")
                    .font(.title3.weight(.medium))

                Spacer()

                Text(state.latestRelays.isEmpty ? "Empty" : "Updated")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(mainTextColor.opacity(0.08), in: Capsule())
                    .foregroundStyle(secondaryTextColor)
            }

            if state.latestRelays.isEmpty {
                Text("No relays yet. Hold the hotkey and speak to generate your first relay.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(secondaryTextColor)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(state.latestRelays.prefix(5).enumerated()), id: \.offset) { _, relay in
                        Text(relay)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(mainTextColor.opacity(0.94))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(mainTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var homePromoCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            PromoHeadlineView(baseColor: mainTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("2relay transforms your voice into clean English prompts. Speak naturally, keep your flow, and paste polished prompts anywhere.")
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(mainTextColor.opacity(0.92))
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)

            Text("Local-first. No external API calls.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(promotionalCardBackgroundColor, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(mainTextColor.opacity(0.12), lineWidth: 1)
        )
    }

    private var dictionaryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Dictionary")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(mainTextColor)

                Text("Prevent common misspellings in final prompts. Example: cloud -> Claude.")
                    .font(.title3)
                    .foregroundStyle(secondaryTextColor)

                dictionaryAddCard
                dictionaryListCard
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
    }

    private var dictionaryAddCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add correction")
                .font(.title3.weight(.medium))

            HStack(spacing: 8) {
                TextField("Heard as (e.g. cloud)", text: $dictionarySourceInput)
                    .textFieldStyle(.roundedBorder)

                Image(systemName: "arrow.right")
                    .foregroundStyle(secondaryTextColor)

                TextField("Replace with (e.g. Claude)", text: $dictionaryReplacementInput)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    saveDictionaryCorrection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    dictionarySourceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || dictionaryReplacementInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dictionaryListCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved corrections")
                    .font(.title3.weight(.medium))
                Spacer()
                Text("\(misspellingDictionary.entries.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(mainTextColor.opacity(0.08), in: Capsule())
                    .foregroundStyle(secondaryTextColor)
            }

            if misspellingDictionary.entries.isEmpty {
                Text("No corrections yet. Add one above to start preventing misspellings.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(secondaryTextColor)
            } else {
                VStack(spacing: 8) {
                    ForEach(misspellingDictionary.entries) { entry in
                        HStack(spacing: 10) {
                            Text(entry.source)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(mainTextColor)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(secondaryTextColor)
                            Text(entry.replacement)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(mainTextColor)
                            Spacer()
                            Button {
                                misspellingDictionary.remove(id: entry.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(mainTextColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func saveDictionaryCorrection() {
        let saved = misspellingDictionary.addOrUpdate(
            source: dictionarySourceInput,
            replacement: dictionaryReplacementInput
        )
        guard saved else {
            return
        }

        dictionarySourceInput = ""
        dictionaryReplacementInput = ""
    }

    private var shortcutsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Shortcuts")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(mainTextColor)

                Text("Configure your push-to-talk shortcut now. More reusable text shortcuts are coming soon.")
                    .font(.title3)
                    .foregroundStyle(secondaryTextColor)

                shortcutsHotkeyCard
                shortcutsComingSoonCard
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
    }

    private var shortcutsHotkeyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Push-to-talk section
            VStack(alignment: .leading, spacing: 6) {
                Text("Push-to-talk")
                    .font(.title3.weight(.medium))

                Text("Hold Fn to record. Release to stop and transcribe.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)

                HStack(spacing: 8) {
                    Text("Shortcut:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                    Text("Fn (hold)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mainTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(mainTextColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }

            Divider()
                .opacity(0.5)

            // Hands-free toggle section
            VStack(alignment: .leading, spacing: 6) {
                Text("Hands-free")
                    .font(.title3.weight(.medium))

                Text("Press to start listening. Press again to stop. No need to hold.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)

                Text("Tap the field below to set your shortcut.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(secondaryTextColor)

                HotkeyRecorderField(name: .relayListen) { shortcut in
                    let shortcutText = shortcut?.description ?? "None"
                    state.reportStatus("Hands-free shortcut updated: \(shortcutText)", level: .success)
                }
                .frame(height: 28)

                HStack(spacing: 8) {
                    Text("Current:")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                    Text(KeyboardShortcuts.getShortcut(for: .relayListen)?.description ?? "Shift+Option+Space")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(mainTextColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shortcutsComingSoonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Other shortcuts coming soon")
                .font(.title3.weight(.medium))
                .italic()
                .foregroundStyle(mainTextColor.opacity(0.58))

            Text("Examples you will be able to save:")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryTextColor)

            VStack(alignment: .leading, spacing: 6) {
                Text("my email address -> me@yourmail.com")
                Text("my X profile -> @mes28io")
                Text("my GitHub -> github.com/mes28io")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(mainTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerCard: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    if let logo = AppBranding.loadLogoImage() {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                Text("2relay")
                    .font(.title2.weight(.semibold))
                }
                Text(state.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            Text(state.overlayState.title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(statusColor.opacity(0.16), in: Capsule())
                .foregroundStyle(statusColor)
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Send Target")
                    .font(.title3.weight(.medium))
                Spacer()
                Text(state.defaultTarget.displayName)
                    .font(.subheadline)
                    .foregroundStyle(secondaryTextColor)
            }

            Text("2relay pastes into whichever app is focused when you send.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = state.overlayErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button("Record 3s + Translate (Test)") {
                    onRunWhisperTestFlow()
                }

                Button("Settings...") {
                    onOpenSettings()
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(14)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func sidebarActionLabel(title: String, iconName: String, rowID: String) -> some View {
        sidebarRowContent(
            iconName: iconName,
            title: title,
            showsText: !layoutState.isSidebarCollapsed
        )
        .background {
            if hoveredSidebarItemID == rowID {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(mainTextColor.opacity(0.08))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func sidebarRowContent(iconName: String, title: String, showsText: Bool) -> some View {
        HStack(spacing: 0) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 20, height: 20)
                .frame(width: 24, alignment: .leading)
                .padding(.leading, 4)

            if showsText {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 10)
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(mainTextColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 44)
        .padding(.horizontal, 12)
    }

    private func tabTooltipText(for tab: SidebarTab) -> String {
        switch tab {
        case .home:
            return "Home: status, target, actions"
        case .dictionary:
            return "Dictionary: prompt terms and rules"
        case .shortcuts:
            return "Shortcuts: hotkey and reusable snippets"
        }
    }

    private func sidebarTooltipText(for rowID: String) -> String {
        switch rowID {
        case "tab-home":
            return "Home"
        case "tab-dictionary":
            return "Dictionary"
        case "tab-shortcuts":
            return "Shortcuts"
        case "action-settings":
            return "Settings"
        case "action-help":
            return "ask me on x - @mes28io"
        default:
            return ""
        }
    }

    private func tooltipHalfWidth(for text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = (text as NSString).size(withAttributes: attributes).width
        return max(24, (textWidth + 22) / 2)
    }

    private var cardBackgroundColor: Color {
        Color(red: 245 / 255, green: 242 / 255, blue: 234 / 255)
    }

    private var promotionalCardBackgroundColor: Color {
        Color(red: 238 / 255, green: 236 / 255, blue: 216 / 255)
    }

    private var appBackgroundColor: Color {
        Color(red: 250 / 255, green: 248 / 255, blue: 242 / 255)
    }

    private var windowSurfaceColor: Color {
        Color(red: 250 / 255, green: 248 / 255, blue: 242 / 255)
    }

    private var sidebarContainerColor: Color {
        Color(red: 246 / 255, green: 243 / 255, blue: 236 / 255)
    }

    private var mainTextColor: Color {
        Color(red: 79 / 255, green: 78 / 255, blue: 78 / 255)
    }

    private var secondaryTextColor: Color {
        mainTextColor.opacity(0.72)
    }

    private var statusColor: Color {
        switch state.overlayState {
        case .idle:
            return secondaryTextColor
        case .listening:
            return .green
        case .transcribing:
            return .blue
        case .readyToSend:
            return .mint
        case .error:
            return .red
        }
    }

    private func color(for level: AppState.StatusLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private func closeSettingsPanel() {
        state.isSettingsPanelPresented = false
    }
}

private struct PromoHeadlineView: View {
    private let words = ["your editor", "your terminal", "your browser"]
    private let scrambleCharacters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private let baseColor: Color
    private let headlineFontSize: CGFloat = 33
    @State private var activeWordIndex = 0
    @State private var displayedWord = "your editor"

    init(baseColor: Color) {
        self.baseColor = baseColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: -2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Fastest way to talk to ")
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                ZStack(alignment: .leading) {
                    Text(displayedWord)
                        .fontWeight(.bold)
                        .italic()
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(width: wordSlotWidth, alignment: .leading)
                .clipped()
            }
            Text("in any language")
        }
        .font(.system(size: headlineFontSize, weight: .regular, design: .serif))
        .foregroundStyle(baseColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            var index = activeWordIndex
            await MainActor.run {
                displayedWord = words[index]
            }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                index = (index + 1) % words.count
                await runDecryptionTransition(to: words[index])
                await MainActor.run {
                    activeWordIndex = index
                }
            }
        }
    }

    private func runDecryptionTransition(to targetWord: String) async {
        let targetChars = Array(targetWord)
        let iterations = max(8, targetChars.count + 3)

        for step in 0..<iterations {
            guard !Task.isCancelled else {
                return
            }

            let revealCount = max(0, step - 2)
            let mixedChars = targetChars.enumerated().map { offset, targetChar in
                if offset < revealCount {
                    return targetChar
                }

                if targetChar == " " {
                    return " "
                }

                return scrambleCharacters.randomElement() ?? targetChar
            }

            await MainActor.run {
                displayedWord = String(mixedChars)
            }
            try? await Task.sleep(nanoseconds: 36_000_000)
        }

        await MainActor.run {
            withAnimation(.easeOut(duration: 0.12)) {
                displayedWord = targetWord
            }
        }
    }

    private var wordSlotWidth: CGFloat {
        let font = NSFont.boldSystemFont(ofSize: headlineFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let worstCaseScrambleWords = words.map { word in
            word.map { $0 == " " ? " " : "W" }.reduce(into: "") { partialResult, character in
                partialResult.append(character)
            }
        }
        let widestWord = (words + worstCaseScrambleWords)
            .map { ($0 as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        return ceil(widestWord + 16)
    }
}

private struct PointingHandCursorOnHover: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard hovering != isHovering else {
                    return
                }

                if hovering {
                    NSCursor.pointingHand.push()
                    isHovering = true
                } else {
                    NSCursor.pop()
                    isHovering = false
                }
            }
            .onDisappear {
                if isHovering {
                    NSCursor.pop()
                    isHovering = false
                }
            }
    }
}

private extension View {
    func pointingHandCursorOnHover() -> some View {
        modifier(PointingHandCursorOnHover())
    }
}

private struct SidebarItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
