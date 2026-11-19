import SwiftUI
import MaagicalCore

/// Dictation: its shortcuts, the transcription and cleanup models, the microphone and the
/// start and stop sound.
struct DictationPane: View {
    @Environment(AppContainer.self) private var container
    @State private var microphones: [AudioDevice] = []

    var body: some View {
        @Bindable var prefs = container.preferences
        Form {
            PaneHeader(.dictation, subtitle: "Speak, and the cleaned-up text is pasted where you type.")
            Section {
                ShortcutRecorder("Dictate", hint: "Hold to talk, release to paste", name: .record)
                ShortcutRecorder("Hands-free", hint: "Press to start, press again to stop", name: .recordToggle)
                ShortcutRecorder("Paste last dictation", name: .pasteLastDictation)
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Smart read, read and dictate sit on the three keys right above Option: , . - on a German keyboard, , . / on a US one. Escape cancels a dictation; nothing is pasted.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ModelPicker(title: "Language", options: ModelOptions.dictationLanguage, selection: $prefs.dictationLanguage)
                ModelPicker(title: "Transcription model", options: ModelOptions.transcription, selection: $prefs.transcriptionModel)
                ModelPicker(title: "Cleanup model", options: ModelOptions.cleanup, selection: $prefs.cleanupModel)
                PromptsLink(page: .feature(.dictation))
            } header: {
                Text("Transcription")
            } footer: {
                Text("Automatic guesses the language for each dictation and can get short ones wrong. Pick the language you speak for the most accurate text.")
                    .foregroundStyle(.secondary)
            }
            Section("Input") {
                DevicePicker(title: "Microphone", automaticLabel: "Automatic", devices: microphones, selection: $prefs.microphoneUID)
                Toggle("Sound when dictation starts, stops or is cancelled", isOn: $prefs.dictationSounds)
            }
        }
        .formStyle(.grouped)
        .task { microphones = AudioDevices.inputs() }
        .onChange(of: prefs.dictationLanguage) { container.onDeviceModel.prepare(language: prefs.dictationLanguageTag) }
    }
}
