import AVFoundation
import Foundation
import Testing
@testable import MaagicalCore

@Suite("Last generation: capture and export") @MainActor
struct GenerationCaptureTests {
    @Test func aCompleteReadHandsOnAllOfItsAudio() async {
        let h = ElevenLabsHarness()
        var generations: [Data] = []
        h.provider.onGeneration = { generations.append($0) }
        h.client.lines = [
            ElevenLabsHarness.line(samples: 240, characters: ["H"], startTimes: [0]),
            ElevenLabsHarness.line(samples: 100, characters: ["i"], startTimes: [0.1]),
        ]
        let result = await h.collect(h.provider.speak(SpeechRequest(text: "Hi", voiceID: "v")))
        #expect(result.failure == nil)
        #expect(generations.count == 1)
        #expect(generations.first?.count == 680)
    }

    @Test func aDroppedReadIsNotKept() async {
        let h = ElevenLabsHarness()
        var generations: [Data] = []
        h.provider.onGeneration = { generations.append($0) }
        h.client.lines = [ElevenLabsHarness.line(samples: 240, characters: ["A"], startTimes: [0]), "never delivered"]
        h.client.error = URLError(.networkConnectionLost)
        h.client.linesBeforeError = 1
        _ = await h.collect(h.provider.speak(SpeechRequest(text: "Ab", voiceID: "v")))
        #expect(generations.isEmpty)
    }

    @Test func overTheCapNothingIsKept() {
        var capture = GenerationCapture()
        capture.append(Data(count: 10))
        #expect(capture.result?.count == 10)
        capture.append(Data(count: GenerationCapture.maxBytes))
        #expect(capture.result == nil)
        capture.append(Data(count: 10))
        #expect(capture.result == nil, "stays dropped once over")
    }

    @Test func writesAPlayableM4A() throws {
        let seconds = 1.5
        let frames = Int(PCMStreamPlayer.sampleRate * seconds)
        var pcm = Data(capacity: frames * 2)
        for i in 0..<frames {
            let sample = Int16(sin(Double(i) * 2 * .pi * 440 / PCMStreamPlayer.sampleRate) * 8000)
            withUnsafeBytes(of: sample.littleEndian) { pcm.append(contentsOf: $0) }
        }
        #expect(GeneratedAudioFile.duration(ofPCM16: pcm) == seconds)
        let url = FileManager.default.temporaryDirectory.appending(path: "maagical-test-\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        try GeneratedAudioFile.writeM4A(pcm16: pcm, to: url)
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.fileFormat.sampleRate
        #expect(abs(duration - seconds) < 0.1)
    }
}
