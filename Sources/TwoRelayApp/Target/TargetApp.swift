import Foundation

enum TargetApp: String, CaseIterable, Identifiable {
    case clipboard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clipboard:
            return "Anywhere"
        }
    }

    func preferredBundleIdentifiers() -> [String] {
        switch self {
        case .clipboard:
            return []
        }
    }
}
