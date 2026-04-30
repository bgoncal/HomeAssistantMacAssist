import AppKit
import AVFoundation
import Foundation

enum ResponsePlaybackResult {
    case finished
    case interrupted
}

@MainActor
final class SpeechPlaybackService: NSObject, NSSoundDelegate {
    private enum SoundRole {
        case response
        case feedback
    }

    private var responseSounds: [NSSound] = []
    private var feedbackSounds: [NSSound] = []
    private var responseContinuations: [ObjectIdentifier: CheckedContinuation<ResponsePlaybackResult, Never>] = [:]

    func playDownloadedAudio(from url: URL, outputUID: String?) async throws -> ResponsePlaybackResult {
        stopResponsePlayback()
        let (data, _) = try await URLSession.shared.data(from: url)
        return try await playResponse(data: data, outputUID: outputUID)
    }

    @discardableResult
    func pauseResponsePlayback() -> Bool {
        let playingSounds = responseSounds.filter(\.isPlaying)
        guard !playingSounds.isEmpty else {
            return false
        }

        playingSounds.forEach {
            $0.pause()
            completeResponsePlayback($0, result: .interrupted, removeSound: false)
        }
        return true
    }

    func stopResponsePlayback() {
        let sounds = responseSounds
        sounds.forEach {
            $0.delegate = nil
            $0.stop()
            completeResponsePlayback($0, result: .interrupted, removeSound: true)
        }
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

        try? playPCM(pcm, rate: sampleRate, channels: 1, outputUID: outputUID, role: .feedback)
    }

    @MainActor
    private func playPCM(_ pcm: Data, rate: Int, channels: Int, outputUID: String?, role: SoundRole) throws {
        try play(data: WAVEncoding.wrapPCM16(pcm, sampleRate: rate, channels: channels), outputUID: outputUID, role: role)
    }

    @MainActor
    private func play(data: Data, outputUID: String?, role: SoundRole) throws {
        guard let sound = NSSound(data: data) else {
            throw PlaybackError.unsupportedAudio
        }
        if let outputUID, !outputUID.isEmpty {
            sound.playbackDeviceIdentifier = outputUID
        }
        sound.delegate = self
        switch role {
        case .response:
            responseSounds.append(sound)
        case .feedback:
            feedbackSounds.append(sound)
        }
        sound.play()
    }

    @MainActor
    private func playResponse(data: Data, outputUID: String?) async throws -> ResponsePlaybackResult {
        guard let sound = NSSound(data: data) else {
            throw PlaybackError.unsupportedAudio
        }
        if let outputUID, !outputUID.isEmpty {
            sound.playbackDeviceIdentifier = outputUID
        }
        sound.delegate = self
        responseSounds.append(sound)

        return await withCheckedContinuation { continuation in
            responseContinuations[ObjectIdentifier(sound)] = continuation
            if !sound.play() {
                completeResponsePlayback(sound, result: .interrupted, removeSound: true)
            }
        }
    }

    func sound(_ sound: NSSound, didFinishPlaying finishedPlaying: Bool) {
        if responseSounds.contains(where: { $0 === sound }) {
            completeResponsePlayback(sound, result: finishedPlaying ? .finished : .interrupted, removeSound: true)
        }
        feedbackSounds.removeAll { $0 === sound }
    }

    private func completeResponsePlayback(_ sound: NSSound, result: ResponsePlaybackResult, removeSound: Bool) {
        responseContinuations.removeValue(forKey: ObjectIdentifier(sound))?.resume(returning: result)
        if removeSound {
            responseSounds.removeAll { $0 === sound }
        }
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
