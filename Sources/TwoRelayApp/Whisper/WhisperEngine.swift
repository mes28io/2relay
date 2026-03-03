@preconcurrency import AVFoundation
import Foundation

#if canImport(whisper)
import whisper
#endif

enum WhisperTask {
    case transcribe
    case translateToEnglish
}

enum WhisperEngineError: LocalizedError {
    case modelPathMissing
    case modelFileNotFound(String)
    case unableToDecodeAudio
    case noAudioSamples
    case contextInitializationFailed(String)
    case inferenceFailed(Int32)
    case whisperModuleNotLinked
    case whisperCLINotFound
    case whisperCLIInvocationFailed(String)
    case whisperCLIOutputMissing

    var errorDescription: String? {
        switch self {
        case .modelPathMissing:
            return "Whisper model path is empty. Set it in Settings."
        case let .modelFileNotFound(path):
            return "Whisper model file not found at: \(path)"
        case .unableToDecodeAudio:
            return "Unable to decode audio into float samples for Whisper."
        case .noAudioSamples:
            return "No audio samples were decoded from the input file."
        case let .contextInitializationFailed(path):
            return "Failed to initialize Whisper context using model: \(path)"
        case let .inferenceFailed(code):
            return "whisper_full failed with code \(code)."
        case .whisperModuleNotLinked:
            return "whisper module is not linked. Add whisper.xcframework to the app target."
        case .whisperCLINotFound:
            return "whisper module is not linked and no whisper CLI was found. Install whisper.cpp CLI or link whisper.xcframework."
        case let .whisperCLIInvocationFailed(details):
            return "whisper CLI failed: \(details)"
        case .whisperCLIOutputMissing:
            return "whisper CLI finished but did not produce transcript output."
        }
    }
}

// Mirrors the whisper.swiftui pattern: single-threaded context access via an actor.
actor WhisperEngine {
    private var configuredModelPath: String

#if canImport(whisper)
    private var context: OpaquePointer?
    private var loadedModelPath: String?
#endif

    init(modelPath: String) {
        self.configuredModelPath = modelPath
    }

    deinit {
#if canImport(whisper)
        if let context {
            whisper_free(context)
        }
#endif
    }

    func updateModelPath(_ modelPath: String) {
        configuredModelPath = modelPath

#if canImport(whisper)
        if loadedModelPath != expandedModelPath(from: modelPath) {
            if let context {
                whisper_free(context)
            }
            context = nil
            loadedModelPath = nil
        }
#endif
    }

    func transcribeOrTranslate(audioURL: URL, task: WhisperTask) async throws -> String {
        let resolvedModelPath = expandedModelPath(from: configuredModelPath)
        guard !resolvedModelPath.isEmpty else {
            throw WhisperEngineError.modelPathMissing
        }

        guard FileManager.default.fileExists(atPath: resolvedModelPath) else {
            throw WhisperEngineError.modelFileNotFound(resolvedModelPath)
        }

        let samples = try Self.decodeAudioToMono16kFloatSamples(from: audioURL)
        guard !samples.isEmpty else {
            throw WhisperEngineError.noAudioSamples
        }

#if canImport(whisper)
        let context = try initializeContextIfNeeded(modelPath: resolvedModelPath)

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.no_context = true
        params.single_segment = false
        params.n_threads = Int32(Self.recommendedThreadCount())

        var languagePointer: UnsafeMutablePointer<CChar>?
        defer {
            if let languagePointer {
                free(languagePointer)
            }
        }

        switch task {
        case .transcribe:
            params.translate = false
        case .translateToEnglish:
            params.translate = true
            languagePointer = strdup("en")
            params.language = UnsafePointer(languagePointer)
            params.detect_language = false
        }

        let result: Int32 = samples.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return -1
            }
            whisper_reset_timings(context)
            return whisper_full(context, params, baseAddress, Int32(buffer.count))
        }

        guard result == 0 else {
            throw WhisperEngineError.inferenceFailed(result)
        }

        let segmentCount = whisper_full_n_segments(context)
        var output = ""
        output.reserveCapacity(Int(segmentCount) * 32)

        for index in 0..<segmentCount {
            guard let segmentCString = whisper_full_get_segment_text(context, index) else {
                continue
            }
            output += String(cString: segmentCString)
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
#else
        _ = samples
        return try transcribeUsingCLI(audioURL: audioURL, modelPath: resolvedModelPath, task: task)
#endif
    }

#if canImport(whisper)
    private func initializeContextIfNeeded(modelPath: String) throws -> OpaquePointer {
        if let context, loadedModelPath == modelPath {
            return context
        }

        if let context {
            whisper_free(context)
            self.context = nil
            loadedModelPath = nil
        }

        var contextParams = whisper_context_default_params()
        contextParams.flash_attn = true

        guard let context = whisper_init_from_file_with_params(modelPath, contextParams) else {
            throw WhisperEngineError.contextInitializationFailed(modelPath)
        }

        self.context = context
        loadedModelPath = modelPath
        return context
    }
#endif

    private static func decodeAudioToMono16kFloatSamples(from audioURL: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: audioURL)
        let sourceFormat = file.processingFormat

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(AudioRecorder.whisperSampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperEngineError.unableToDecodeAudio
        }

        let sourceFrameCount = AVAudioFrameCount(file.length)
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: sourceFrameCount
        ) else {
            throw WhisperEngineError.unableToDecodeAudio
        }

        try file.read(into: sourceBuffer)

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw WhisperEngineError.unableToDecodeAudio
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let estimatedFrames = AVAudioFrameCount(max(1, ceil(Double(sourceBuffer.frameLength) * ratio)))

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: estimatedFrames
        ) else {
            throw WhisperEngineError.unableToDecodeAudio
        }

        var conversionError: NSError?
        var sourceConsumed = false

        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if sourceConsumed {
                outStatus.pointee = .endOfStream
                return nil
            }

            sourceConsumed = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        guard conversionError == nil, status != .error else {
            throw WhisperEngineError.unableToDecodeAudio
        }

        guard let channelData = convertedBuffer.floatChannelData?.pointee else {
            throw WhisperEngineError.unableToDecodeAudio
        }

        let frameLength = Int(convertedBuffer.frameLength)
        return Array(UnsafeBufferPointer(start: channelData, count: frameLength))
    }

    private static func recommendedThreadCount() -> Int {
        let cpuCount = ProcessInfo.processInfo.processorCount
        return max(1, min(8, cpuCount - 2))
    }

    private func transcribeUsingCLI(audioURL: URL, modelPath: String, task: WhisperTask) throws -> String {
        let outputPrefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("2relay-whisper-\(UUID().uuidString)").path
        defer {
            removeCLIOutputFiles(prefix: outputPrefix)
        }

        let commands = Self.resolveCLICommands()
        guard !commands.isEmpty else {
            throw WhisperEngineError.whisperCLINotFound
        }

        var lastFailure = "unknown error"

        for command in commands {
            for argVariant in Self.cliArgumentVariants(
                modelPath: modelPath,
                audioPath: audioURL.path,
                outputPrefix: outputPrefix,
                task: task
            ) {
                let arguments = command.baseArguments + argVariant
                do {
                    let result = try Self.runProcess(
                        executableURL: command.executableURL,
                        arguments: arguments
                    )

                    if result.status != 0 {
                        let details = Self.condensedFailureOutput(stdout: result.stdout, stderr: result.stderr)
                        lastFailure = "\(command.displayName) exited with \(result.status). \(details)"
                        continue
                    }

                    if let transcript = Self.readCLITranscript(prefix: outputPrefix) {
                        return transcript
                    }

                    lastFailure = "\(command.displayName) completed but transcript file was missing."
                } catch {
                    lastFailure = "\(command.displayName) failed to run: \(error.localizedDescription)"
                }
            }
        }

        if lastFailure.contains("transcript file was missing") {
            throw WhisperEngineError.whisperCLIOutputMissing
        }
        throw WhisperEngineError.whisperCLIInvocationFailed(lastFailure)
    }

    private func removeCLIOutputFiles(prefix: String) {
        let extensions = ["txt", "json", "srt", "vtt", "csv", "wts"]
        for ext in extensions {
            let path = "\(prefix).\(ext)"
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private static func readCLITranscript(prefix: String) -> String? {
        let transcriptPath = "\(prefix).txt"
        guard let data = FileManager.default.contents(atPath: transcriptPath),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func condensedFailureOutput(stdout: String, stderr: String) -> String {
        let combined = [stderr, stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
        if combined.isEmpty {
            return "No output."
        }
        if combined.count <= 320 {
            return combined
        }
        return "\(combined.prefix(320))..."
    }

    private static func cliArgumentVariants(
        modelPath: String,
        audioPath: String,
        outputPrefix: String,
        task: WhisperTask
    ) -> [[String]] {
        var short = [
            "-m", modelPath,
            "-f", audioPath,
            "-of", outputPrefix,
            "-otxt",
            "-np",
            "-nt"
        ]

        switch task {
        case .transcribe:
            break
        case .translateToEnglish:
            short += ["-tr", "-l", "en"]
        }

        var long = [
            "--model", modelPath,
            "--file", audioPath,
            "--output-file", outputPrefix,
            "--output-txt",
            "--no-prints",
            "--no-timestamps"
        ]

        switch task {
        case .transcribe:
            break
        case .translateToEnglish:
            long += ["--translate", "--language", "en"]
        }

        return [short, long]
    }

    private struct CLICommand {
        let executableURL: URL
        let baseArguments: [String]
        let displayName: String
    }

    private static func resolveCLICommands() -> [CLICommand] {
        var commands: [CLICommand] = []
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        if let overridePath = environment["WHISPER_CPP_CLI"], !overridePath.isEmpty {
            let expanded = NSString(string: overridePath).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expanded) {
                commands.append(
                    CLICommand(
                        executableURL: URL(fileURLWithPath: expanded),
                        baseArguments: [],
                        displayName: expanded
                    )
                )
            }
        }

        for absolutePath in [
            "/opt/homebrew/bin/whisper-cli",
            "/usr/local/bin/whisper-cli",
            "/opt/homebrew/bin/main",
            "/usr/local/bin/main"
        ] {
            if fileManager.isExecutableFile(atPath: absolutePath) {
                commands.append(
                    CLICommand(
                        executableURL: URL(fileURLWithPath: absolutePath),
                        baseArguments: [],
                        displayName: absolutePath
                    )
                )
            }
        }

        commands.append(
            CLICommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                baseArguments: ["whisper-cli"],
                displayName: "whisper-cli (PATH)"
            )
        )
        commands.append(
            CLICommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                baseArguments: ["main"],
                displayName: "main (PATH)"
            )
        )

        var unique: [CLICommand] = []
        var seen = Set<String>()
        for command in commands {
            let key = "\(command.executableURL.path)|\(command.baseArguments.joined(separator: " "))"
            if seen.insert(key).inserted {
                unique.append(command)
            }
        }
        return unique
    }

    private struct ProcessResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static func runProcess(executableURL: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    private func expandedModelPath(from configuredPath: String) -> String {
        NSString(string: configuredPath).expandingTildeInPath
    }
}
