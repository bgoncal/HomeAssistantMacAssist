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
        }
        .formStyle(.grouped)
        .padding()
    }
}
