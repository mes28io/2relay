import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case alreadyRecording
    case notRecording
    case microphonePermissionDenied
    case conversionUnavailable
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No recording is currently in progress."
        case .microphonePermissionDenied:
            return "Microphone access is not granted."
        case .conversionUnavailable:
            return "Could not configure audio conversion to 16kHz mono PCM."
        case .noAudioCaptured:
            return "No audio samples were captured."
        }
    }
}

final class AudioRecorder {
    static let whisperSampleRate = 16_000

    private let engine: AVAudioEngine
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()

    private var converter: AVAudioConverter?
    private var pcmData = Data()
    private(set) var isRecording = false

    init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        self.targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(Self.whisperSampleRate),
            channels: 1,
            interleaved: true
        )!
    }

    func start() throws {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        guard Self.microphoneIsAuthorized() else {
            throw AudioRecorderError.microphonePermissionDenied
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.conversionUnavailable
        }

        lock.lock()
        self.converter = converter
        pcmData.removeAll(keepingCapacity: true)
        isRecording = true
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            lock.lock()
            self.converter = nil
            isRecording = false
            lock.unlock()
            throw error
        }
    }

    func stop() throws -> URL {
        guard isRecording else {
            throw AudioRecorderError.notRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        isRecording = false
        converter = nil
        let capturedPCM = pcmData
        pcmData.removeAll(keepingCapacity: false)
        lock.unlock()

        guard !capturedPCM.isEmpty else {
            throw AudioRecorderError.noAudioCaptured
        }

        return try makeTemporaryWAVFile(from: capturedPCM, sampleRate: Self.whisperSampleRate)
    }

    func makeTemporaryWAVFile(from pcmData: Data, sampleRate: Int = whisperSampleRate) throws -> URL {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("2relay-recording-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        try WAVFileWriter.writePCM16Mono(pcmData: pcmData, sampleRate: sampleRate, to: outputURL)
        return outputURL
    }

    private func handleInputBuffer(_ inputBuffer: AVAudioPCMBuffer) {
        lock.lock()
        let converter = self.converter
        let activelyRecording = isRecording
        lock.unlock()

        guard activelyRecording, let converter else {
            return
        }

        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(max(1, ceil(Double(inputBuffer.frameLength) * ratio)))

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            return
        }

        var conversionError: NSError?
        var inputProvided = false

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputProvided {
                outStatus.pointee = .noDataNow
                return nil
            }

            inputProvided = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard conversionError == nil, status != .error else {
            return
        }

        let audioBuffer = outputBuffer.audioBufferList.pointee.mBuffers
        guard let dataPointer = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else {
            return
        }

        let byteCount = Int(audioBuffer.mDataByteSize)
        let bytes = dataPointer.bindMemory(to: UInt8.self, capacity: byteCount)

        lock.lock()
        pcmData.append(bytes, count: byteCount)
        lock.unlock()
    }

    private static func microphoneIsAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

enum WAVFileWriter {
    static func writePCM16Mono(pcmData: Data, sampleRate: Int, to url: URL) throws {
        var fileData = Data()
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        fileData.append("RIFF".data(using: .ascii)!)
        fileData.appendLE(chunkSize)
        fileData.append("WAVE".data(using: .ascii)!)
        fileData.append("fmt ".data(using: .ascii)!)
        fileData.appendLE(UInt32(16))
        fileData.appendLE(UInt16(1))
        fileData.appendLE(channels)
        fileData.appendLE(UInt32(sampleRate))
        fileData.appendLE(byteRate)
        fileData.appendLE(blockAlign)
        fileData.appendLE(bitsPerSample)
        fileData.append("data".data(using: .ascii)!)
        fileData.appendLE(dataSize)
        fileData.append(pcmData)

        try fileData.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
