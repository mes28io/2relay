import AVFoundation
import XCTest
@testable import TwoRelayApp

final class AudioRecorderTests: XCTestCase {
    func testTemporaryWAVFileExistsAndHasDuration() throws {
        let recorder = AudioRecorder()
        let pcmData = makeSineWavePCM16(sampleRate: AudioRecorder.whisperSampleRate, durationSeconds: 0.25)

        let outputURL = try recorder.makeTemporaryWAVFile(from: pcmData, sampleRate: AudioRecorder.whisperSampleRate)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let audioFile = try AVAudioFile(forReading: outputURL)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        XCTAssertEqual(Int(audioFile.processingFormat.sampleRate), AudioRecorder.whisperSampleRate)
        XCTAssertEqual(audioFile.processingFormat.channelCount, 1)
        XCTAssertGreaterThan(duration, 0.0)
    }

    private func makeSineWavePCM16(sampleRate: Int, durationSeconds: Double, frequency: Double = 440) -> Data {
        let frameCount = Int(Double(sampleRate) * durationSeconds)
        var data = Data(capacity: frameCount * MemoryLayout<Int16>.size)

        for frame in 0..<frameCount {
            let sample = sin(2.0 * .pi * frequency * Double(frame) / Double(sampleRate))
            let scaled = Int16((sample * Double(Int16.max)).rounded())
            var littleEndian = scaled.littleEndian
            Swift.withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        return data
    }
}
