import AVFoundation
import Foundation

/// The PCM of one ElevenLabs generation, kept while it streams so the last read can be
/// saved or shared (Save / Share in the panel). Only a generation whose audio arrived in
/// full is handed on; a stopped or failed stream keeps the previous one.
struct GenerationCapture {
    /// 30 minutes of 16-bit mono 24 kHz audio (about 86 MB); longer generations are not kept.
    static let maxBytes = 30 * 60 * Int(PCMStreamPlayer.sampleRate) * 2

    private(set) var pcm = Data()
    private(set) var overflowed = false

    mutating func append(_ chunk: Data) {
        guard !overflowed else { return }
        guard pcm.count + chunk.count <= Self.maxBytes else {
            overflowed = true
            pcm = Data()
            return
        }
        pcm.append(chunk)
    }

    /// The whole generation, nil when nothing arrived or it ran past the cap.
    var result: Data? { overflowed || pcm.isEmpty ? nil : pcm }
}

/// Writes generated speech to a file people can play anywhere.
public enum GeneratedAudioFile {
    public static let fileExtension = "m4a"

    /// Seconds of audio in 16-bit mono 24 kHz PCM.
    public static func duration(ofPCM16 pcm: Data) -> Double {
        Double(pcm.count / 2) / PCMStreamPlayer.sampleRate
    }

    /// Encodes 16-bit little-endian mono 24 kHz PCM as AAC in an .m4a container.
    public static func writeM4A(pcm16: Data, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: PCMStreamPlayer.sampleRate, channels: 1)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: PCMStreamPlayer.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let totalFrames = pcm16.count / 2
        let chunkFrames = 24_000
        var frame = 0
        try pcm16.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            while frame < totalFrames {
                let count = min(chunkFrames, totalFrames - frame)
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
                buffer.frameLength = AVAudioFrameCount(count)
                let out = buffer.floatChannelData![0]
                for i in 0..<count {
                    out[i] = Float(Int16(littleEndian: samples[frame + i])) / 32768.0
                }
                try file.write(from: buffer)
                frame += count
            }
        }
    }
}
