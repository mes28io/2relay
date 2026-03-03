import Foundation

struct MisspellingCorrection: Identifiable, Codable, Equatable {
    let id: UUID
    var source: String
    var replacement: String

    init(id: UUID = UUID(), source: String, replacement: String) {
        self.id = id
        self.source = source
        self.replacement = replacement
    }
}

@MainActor
final class MisspellingDictionary: ObservableObject {
    @Published private(set) var entries: [MisspellingCorrection] = []

    private let storage: UserDefaults
    private let storageKey: String

    init(
        storage: UserDefaults = .standard,
        storageKey: String = "com.2relay.misspellingCorrections"
    ) {
        self.storage = storage
        self.storageKey = storageKey
        load()
    }

    @discardableResult
    func addOrUpdate(source: String, replacement: String) -> Bool {
        let normalizedSource = normalizeInput(source)
        let normalizedReplacement = normalizeInput(replacement)
        guard !normalizedSource.isEmpty, !normalizedReplacement.isEmpty else {
            return false
        }

        if let index = entries.firstIndex(where: { normalizeKey($0.source) == normalizeKey(normalizedSource) }) {
            entries[index].source = normalizedSource
            entries[index].replacement = normalizedReplacement
        } else {
            entries.append(MisspellingCorrection(source: normalizedSource, replacement: normalizedReplacement))
        }

        sortEntries()
        save()
        return true
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func apply(to text: String) -> String {
        let sortedEntries = entries.sorted { $0.source.count > $1.source.count }
        var output = text

        for entry in sortedEntries {
            output = replacingCaseInsensitiveToken(
                in: output,
                source: entry.source,
                replacement: entry.replacement
            )
        }

        return output
    }

    private func load() {
        guard let data = storage.data(forKey: storageKey) else {
            return
        }

        guard let decoded = try? JSONDecoder().decode([MisspellingCorrection].self, from: data) else {
            return
        }

        entries = decoded
        sortEntries()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        storage.set(data, forKey: storageKey)
    }

    private func sortEntries() {
        entries.sort { lhs, rhs in
            normalizeKey(lhs.source) < normalizeKey(rhs.source)
        }
    }

    private func normalizeInput(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeKey(_ value: String) -> String {
        normalizeInput(value).lowercased()
    }

    private func replacingCaseInsensitiveToken(
        in text: String,
        source: String,
        replacement: String
    ) -> String {
        let sourceTokens = source
            .split(whereSeparator: \.isWhitespace)
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !sourceTokens.isEmpty else {
            return text
        }

        let tokenBody = sourceTokens.joined(separator: #"\s+"#)
        let pattern = #"\b\#(tokenBody)\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: nsRange,
            withTemplate: replacement
        )
    }
}
