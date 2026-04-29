import Foundation

struct AppSettings: Codable, Equatable {
    var homeAssistantURL = "http://homeassistant.local:8123"
    var accessToken = ""
    var pipelineID = ""
    var useWakeWord = true
    var selectedInputUID = ""
    var selectedOutputUID = ""
    var launchAtLogin = false
    var startListeningOnLaunch = false

    var hasHomeAssistantConnection: Bool {
        !homeAssistantURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
