import SwiftUI

@main
struct HomeAssistantMacVPEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Home Assistant Mac VPE") {
            ContentView(model: model)
                .frame(minWidth: 1040, minHeight: 620)
                .task {
                    await model.start()
                }
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Refresh Audio Devices") {
                    model.refreshAudioDevices()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button(model.isSessionActive ? "Stop Listening" : "Start Listening") {
                    Task {
                        await model.toggleSession()
                    }
                }
                .keyboardShortcut(.space, modifiers: [.command])
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 560)
        }
    }
}
