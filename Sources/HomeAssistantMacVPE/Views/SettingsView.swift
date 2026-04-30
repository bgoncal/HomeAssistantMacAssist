import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Home Assistant") {
                TextField("URL", text: model.binding(\.homeAssistantURL))
                SecureField("Long-lived access token", text: model.binding(\.accessToken))
                PipelinePicker(model: model)
                Toggle("Start listening when the app opens", isOn: model.binding(\.startListeningOnLaunch))
            }

            Section("Sound Feedback") {
                Toggle("Wake word detected", isOn: model.binding(\.playWakeWordSound))
                Toggle("Processing started", isOn: model.binding(\.playProcessingSound))
                Toggle("Ready for wake word", isOn: model.binding(\.playReadyForWakeWordSound))
            }

            Section("Audio Processing") {
                ProcessingSlider(
                    title: "Mic gain",
                    value: model.clampedDoubleBinding(\.micGain, range: 0.25...12.0),
                    range: 0.25...12.0,
                    step: 0.25,
                    valueText: String(format: "%.2fx", model.settings.micGain)
                )

                ProcessingSlider(
                    title: "Noise suppression",
                    value: model.integerSliderBinding(\.noiseSuppressionLevel, range: 0...4),
                    range: 0...4,
                    step: 1,
                    valueText: "\(model.settings.noiseSuppressionLevel)"
                )

                ProcessingSlider(
                    title: "Auto gain",
                    value: model.integerSliderBinding(\.autoGainDBFS, range: 0...31),
                    range: 0...31,
                    step: 1,
                    valueText: "\(model.settings.autoGainDBFS) dBFS"
                )
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
