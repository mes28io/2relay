import Foundation

struct PromptCleaner {
    enum Style: String, CaseIterable {
        case claudeCode = "ClaudeCode"
        case codex = "Codex"
    }

    func clean(rawText: String, style: Style) -> String {
        let normalized = normalizeWhitespace(rawText)
        let goal = normalized.isEmpty ? "No transcript captured." : normalized
        return "- \(goal)"
    }

    func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removeFillers(from text: String) -> String {
        let patterns = [
            #"\b(um+|uh+|er+|ah+|hmm+)\b"#,
            #"\byou know\b"#,
            #"\bi mean\b"#
        ]

        let stripped = patterns.reduce(text) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return normalizeWhitespace(stripped)
    }

    func removeStutters(from text: String) -> String {
        let withoutHyphenStutter = text.replacingOccurrences(
            of: #"\b([A-Za-z]{1,3})(?:-\1)+\b"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )

        let tokens = withoutHyphenStutter.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else {
            return ""
        }

        var result: [String] = []
        for token in tokens {
            if let last = result.last,
               normalizedToken(last) == normalizedToken(token),
               !normalizedToken(token).isEmpty {
                continue
            }
            result.append(token)
        }

        return normalizeWhitespace(result.joined(separator: " "))
    }

    func removeRepeatedPhrases(from text: String) -> String {
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count > 3 else {
            return text
        }

        var index = 0
        var result: [String] = []

        while index < tokens.count {
            var collapsed = false
            let remaining = tokens.count - index
            let maxWindow = min(4, remaining / 2)

            if maxWindow >= 2 {
                for window in stride(from: maxWindow, through: 2, by: -1) {
                    let leftRange = index..<(index + window)
                    let rightRange = (index + window)..<(index + (window * 2))

                    let left = tokens[leftRange].map(normalizedToken)
                    let right = tokens[rightRange].map(normalizedToken)

                    if left == right {
                        result.append(contentsOf: tokens[leftRange])
                        index += window * 2
                        collapsed = true
                        break
                    }
                }
            }

            if collapsed {
                continue
            }

            result.append(tokens[index])
            index += 1
        }

        return removeStutters(from: result.joined(separator: " "))
    }

    func splitSentences(from text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func convertVagueToImperative(sentence: String) -> String {
        var updated = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "can you please ",
            "can you ",
            "could you please ",
            "could you ",
            "would you please ",
            "would you ",
            "please ",
            "i need you to ",
            "i want you to ",
            "i need to ",
            "i want to ",
            "we need to ",
            "let's ",
            "let us ",
            "it would be great if you could ",
            "you can "
        ]

        let lowered = updated.lowercased()
        if let matchedPrefix = prefixes.first(where: { lowered.hasPrefix($0) }) {
            updated = String(updated.dropFirst(matchedPrefix.count))
        }

        updated = updated.replacingOccurrences(
            of: #"\b(maybe|just|probably)\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        updated = normalizeWhitespace(updated)

        guard !updated.isEmpty else {
            return ""
        }

        let first = updated.prefix(1).uppercased()
        let rest = updated.dropFirst()
        return first + rest
    }

    func extractContextItems(from text: String) -> [String] {
        var items: [String] = []

        let fileMentions = extractFileMentions(from: text)
        if !fileMentions.isEmpty {
            items.append("Files: \(fileMentions.joined(separator: ", "))")
        }

        let frameworks = extractFrameworkMentions(from: text)
        if !frameworks.isEmpty {
            items.append("Frameworks: \(frameworks.joined(separator: ", "))")
        }

        if items.isEmpty {
            items.append("No explicit files or frameworks were mentioned.")
        }

        return items
    }

    func extractConstraintItems(from sentences: [String]) -> [String] {
        let constraints = sentences
            .filter(isConstraintSentence)
            .map(ensureSentence)

        let unique = uniqueSentences(constraints)
        return unique.isEmpty ? ["None specified."] : unique
    }

    func extractGoal(
        from sentences: [String],
        fullText: String,
        hasContext: Bool,
        hasConstraints: Bool
    ) -> String {
        // If the transcript does not look like a coding request, keep the
        // full cleaned speech so user meaning is preserved.
        if !hasCodingIntent(fullText), !hasContext, !hasConstraints {
            return fullText
        }

        let primarySentences = sentences.filter { !isConstraintSentence($0) && !isContextSentence($0) }
        if !primarySentences.isEmpty {
            return primarySentences.joined(separator: " ")
        }

        let nonConstraint = sentences.filter { !isConstraintSentence($0) }
        if !nonConstraint.isEmpty {
            return nonConstraint.joined(separator: " ")
        }

        return sentences.joined(separator: " ").isEmpty ? "Complete the requested coding task" : sentences.joined(separator: " ")
    }

    func hasCodingIntent(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let keywords = [
            "build",
            "implement",
            "code",
            "fix",
            "debug",
            "refactor",
            "write a function",
            "write tests",
            "swiftui",
            "xcode",
            "claude code",
            "codex",
            "api",
            "framework",
            "file",
            ".swift",
            ".ts",
            ".js",
            ".py"
        ]
        return keywords.contains { lowered.contains($0) }
    }

    func outputFormatLine(for style: Style) -> String {
        switch style {
        case .claudeCode:
            return "Prompt-first markdown optimized for Claude Code terminal flow."
        case .codex:
            return "Implementation summary, changed files, and verification results."
        }
    }

    func renderTemplate(
        goal: String,
        contextItems: [String],
        constraintItems: [String],
        outputFormatLine: String
    ) -> String {
        let contextBlock = contextItems.map { "- \($0)" }.joined(separator: "\n")
        let constraintBlock = constraintItems.map { "- \($0)" }.joined(separator: "\n")

        return """
        Goal:
        - \(goal)

        Context:
        \(contextBlock)

        Constraints:
        \(constraintBlock)

        Output format:
        - \(outputFormatLine)
        """
    }

    func extractFileMentions(from text: String) -> [String] {
        let pattern = #"\b(?:\.{0,2}/)?(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,8}\b"#
        let reservedFrameworkTokens: Set<String> = ["whisper.cpp", "next.js"]

        return uniqueTokens(matching: pattern, in: text).filter { token in
            !reservedFrameworkTokens.contains(token.lowercased())
        }
    }

    func extractFrameworkMentions(from text: String) -> [String] {
        let frameworkMap: [(needle: String, display: String)] = [
            ("swiftui", "SwiftUI"),
            ("whisper.cpp", "whisper.cpp"),
            ("avfoundation", "AVFoundation"),
            ("swift", "Swift"),
            ("react", "React"),
            ("next.js", "Next.js"),
            ("node", "Node.js"),
            ("django", "Django"),
            ("flask", "Flask"),
            ("rails", "Rails"),
            ("fastapi", "FastAPI"),
            ("pytorch", "PyTorch"),
            ("tensorflow", "TensorFlow")
        ]

        let lowered = text.lowercased()
        var found: [String] = []

        for item in frameworkMap where containsKeyword(item.needle, in: lowered) {
            found.append(item.display)
        }

        return uniqueSentences(found)
    }

    func isConstraintSentence(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        let markers = [
            "must",
            "should",
            "without",
            "do not",
            "don't",
            "cannot",
            "can't",
            "no ",
            "only",
            "avoid",
            "required"
        ]

        return markers.contains { lowered.contains($0) }
    }

    func isContextSentence(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        return !extractFileMentions(from: sentence).isEmpty
            || !extractFrameworkMentions(from: sentence).isEmpty
            || lowered.contains("using ")
            || lowered.contains("with ")
    }

    func ensureSentence(_ text: String) -> String {
        let trimmed = normalizeWhitespace(text)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return trimmed
        }

        return trimmed + "."
    }

    func uniqueSentences(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let key = value.lowercased()
            if seen.insert(key).inserted {
                result.append(value)
            }
        }

        return result
    }

    func uniqueTokens(matching pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        var output: [String] = []
        var seen = Set<String>()

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }

            let value = String(text[range])
            if seen.insert(value.lowercased()).inserted {
                output.append(value)
            }
        }

        return output
    }

    func containsKeyword(_ keyword: String, in text: String) -> Bool {
        if keyword.contains(".") {
            return text.contains(keyword)
        }

        let escaped = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = "\\b\(escaped)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, options: [], range: nsRange) != nil
    }

    func normalizedToken(_ token: String) -> String {
        token
            .trimmingCharacters(in: .punctuationCharacters)
            .lowercased()
    }
}
