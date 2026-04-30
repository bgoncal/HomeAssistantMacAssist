import AppKit
import AVFoundation
import Foundation

@MainActor
final class SpeechPlaybackService: NSObject, NSSoundDelegate {
    private var activeSounds: [NSSound] = []

    func playDownloadedAudio(from url: URL, outputUID: String?) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        try play(data: data, outputUID: outputUID)
    }

    func playWakeSound(outputUID: String?) {
        playTone(frequency: 880.0, duration: 0.16, amplitude: 11_000, outputUID: outputUID)
    }

    func playProcessingSound(outputUID: String?) {
        playTone(frequency: 660.0, duration: 0.12, amplitude: 9_000, outputUID: outputUID)
    }

    func playReadyForWakeWordSound(outputUID: String?) {
        playTone(frequency: 520.0, duration: 0.14, amplitude: 8_500, outputUID: outputUID)
    }

    private func playTone(frequency: Double, duration: Double, amplitude: Double, outputUID: String?) {
        let sampleRate = 44_100
        let frameCount = Int(Double(sampleRate) * duration)
        var pcm = Data(capacity: frameCount * 2)

        for frame in 0..<frameCount {
            let progress = Double(frame) / Double(frameCount)
            let envelope = sin(progress * .pi)
            let tone = sin(2.0 * .pi * frequency * Double(frame) / Double(sampleRate))
            var sample = Int16(tone * envelope * amplitude).littleEndian
            pcm.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        try? playPCM(pcm, rate: sampleRate, channels: 1, outputUID: outputUID)
    }

    @MainActor
    func playPCM(_ pcm: Data, rate: Int, channels: Int, outputUID: String?) throws {
        try play(data: WAVEncoding.wrapPCM16(pcm, sampleRate: rate, channels: channels), outputUID: outputUID)
    }

    @MainActor
    func play(data: Data, outputUID: String?) throws {
        guard let sound = NSSound(data: data) else {
            throw PlaybackError.unsupportedAudio
        }
        if let outputUID, !outputUID.isEmpty {
            sound.playbackDeviceIdentifier = outputUID
        }
        sound.delegate = self
        activeSounds.append(sound)
        sound.play()
    }

    func sound(_ sound: NSSound, didFinishPlaying finishedPlaying: Bool) {
        activeSounds.removeAll { $0 === sound }
    }
}

enum PlaybackError: LocalizedError {
    case unsupportedAudio

    var errorDescription: String? {
        "The assistant returned audio in a format macOS could not play."
    }
}

enum WAVEncoding {
    static func wrapPCM16(_ pcm: Data, sampleRate: Int, channels: Int) -> Data {
        let byteRate = sampleRate * channels * 2
        let blockAlign = channels * 2
        let dataSize = UInt32(pcm.count)
        let riffSize = UInt32(36 + pcm.count)

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(littleEndian(riffSize))
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(littleEndian(UInt32(16)))
        data.append(littleEndian(UInt16(1)))
        data.append(littleEndian(UInt16(channels)))
        data.append(littleEndian(UInt32(sampleRate)))
        data.append(littleEndian(UInt32(byteRate)))
        data.append(littleEndian(UInt16(blockAlign)))
        data.append(littleEndian(UInt16(16)))
        data.append("data".data(using: .ascii)!)
        data.append(littleEndian(dataSize))
        data.append(pcm)
        return data
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var little = value.littleEndian
        return Data(bytes: &little, count: MemoryLayout<T>.size)
    }
}
