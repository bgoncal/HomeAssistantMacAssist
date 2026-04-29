import AVFoundation
import CoreAudio
import Foundation

final class AudioCaptureService {
    struct Format {
        static let width = 2
        static let channels: AVAudioChannelCount = 1
        static let softwareGain: Float = 8.0
    }

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private(set) var isCapturing = false
    private var didReportFirstChunk = false

    func start(inputDeviceID: AudioDeviceID?, sampleRate: Double, onDiagnostic: @escaping (String) -> Void = { _ in }, onChunk: @escaping (Data) -> Void) throws {
        stop()
        didReportFirstChunk = false

        let inputNode = engine.inputNode
        if let inputDeviceID, let audioUnit = inputNode.audioUnit {
            var mutableDeviceID = inputDeviceID
            let size = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &mutableDeviceID,
                size
            )
        }

        let sourceFormat = inputNode.outputFormat(forBus: 0)
        onDiagnostic("Mic source format: \(Int(sourceFormat.sampleRate)) Hz, \(sourceFormat.channelCount) channel, \(sourceFormat.commonFormat.label)")
        onDiagnostic("Assist audio stream: \(Int(sampleRate)) Hz, 16-bit, 1 channel, pcm, gain \(Int(Self.Format.softwareGain))x")
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: Self.Format.channels,
            interleaved: false
        ) else {
            throw AudioCaptureError.unavailableFormat
        }

        converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let data = self.convert(buffer, from: sourceFormat, to: targetFormat), !data.isEmpty else {
                return
            }
            if !self.didReportFirstChunk {
                self.didReportFirstChunk = true
                onDiagnostic("Sending PCM16 audio chunks: \(data.count) bytes, peak \(data.pcm16PeakDescription)")
            }
            onChunk(data)
        }

        engine.prepare()
        try engine.start()
        isCapturing = true
    }

    func stop() {
        guard isCapturing || engine.isRunning else {
            return
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        converter = nil
        isCapturing = false
        didReportFirstChunk = false
    }

    private func convert(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) -> Data? {
        guard let converter else {
            return nil
        }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 8
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var didProvideInput = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil else {
            return nil
        }

        return converted.pcm16LittleEndianData(gain: Self.Format.softwareGain)
    }
}

private extension Data {
    var pcm16PeakDescription: String {
        var peak: Int16 = 0
        withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let magnitude = sample == Int16.min ? Int16.max : abs(sample)
                if magnitude > peak {
                    peak = magnitude
                }
            }
        }
        return "\(peak)"
    }
}

private extension AVAudioPCMBuffer {
    func pcm16LittleEndianData(gain: Float) -> Data? {
        let frames = Int(frameLength)
        guard frames > 0 else {
            return nil
        }

        var output = Data(capacity: frames * 2)

        if let floatData = floatChannelData {
            let mono = floatData[0]
            for index in 0..<frames {
                let sample = max(-1.0, min(1.0, mono[index] * gain))
                var intSample = Int16(sample * Float(Int16.max)).littleEndian
                output.append(Data(bytes: &intSample, count: MemoryLayout<Int16>.size))
            }
            return output
        }

        if let int16Data = int16ChannelData {
            let mono = int16Data[0]
            for index in 0..<frames {
                var intSample = mono[index].littleEndian
                output.append(Data(bytes: &intSample, count: MemoryLayout<Int16>.size))
            }
            return output
        }

        return nil
    }
}

private extension AVAudioCommonFormat {
    var label: String {
        switch self {
        case .pcmFormatFloat32:
            "float32"
        case .pcmFormatFloat64:
            "float64"
        case .pcmFormatInt16:
            "int16"
        case .pcmFormatInt32:
            "int32"
        case .otherFormat:
            "other"
        @unknown default:
            "unknown"
        }
    }
}

enum AudioCaptureError: LocalizedError {
    case unavailableFormat

    var errorDescription: String? {
        switch self {
        case .unavailableFormat:
            "Unable to create the 16 kHz mono PCM format Home Assistant expects."
        }
    }
}
