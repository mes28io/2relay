import Foundation

enum ClaudeCodeMode: String, CaseIterable, Identifiable {
    case cursorExtension
    case terminal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursorExtension:
            return "Cursor Extension"
        case .terminal:
            return "Terminal"
        }
    }
}

enum TargetApp: String, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case clipboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .clipboard:
            return "Anywhere"
        }
    }

    func preferredBundleIdentifiers(claudeCodeMode: ClaudeCodeMode) -> [String] {
        switch self {
        case .claudeCode:
            switch claudeCodeMode {
            case .cursorExtension:
                return [
                    "com.todesktop.230313mzl4w4u92",
                    "com.microsoft.VSCode"
                ]
            case .terminal:
                return [
                    "com.apple.Terminal",
                    "com.googlecode.iterm2"
                ]
            }
        case .codex:
            return [
                "com.openai.codex",
                "com.apple.Terminal",
                "com.googlecode.iterm2"
            ]
        case .clipboard:
            return []
        }
    }
}
