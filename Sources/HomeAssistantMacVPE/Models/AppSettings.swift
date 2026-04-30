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
    var playWakeWordSound = true
    var playProcessingSound = true
    var playReadyForWakeWordSound = true
    var micGain = 2.0
    var noiseSuppressionLevel = 0
    var autoGainDBFS = 8

    var hasHomeAssistantConnection: Bool {
        !homeAssistantURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        homeAssistantURL = try container.decodeIfPresent(String.self, forKey: .homeAssistantURL) ?? homeAssistantURL
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? accessToken
        pipelineID = try container.decodeIfPresent(String.self, forKey: .pipelineID) ?? pipelineID
        useWakeWord = try container.decodeIfPresent(Bool.self, forKey: .useWakeWord) ?? useWakeWord
        selectedInputUID = try container.decodeIfPresent(String.self, forKey: .selectedInputUID) ?? selectedInputUID
        selectedOutputUID = try container.decodeIfPresent(String.self, forKey: .selectedOutputUID) ?? selectedOutputUID
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        startListeningOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .startListeningOnLaunch) ?? startListeningOnLaunch
        playWakeWordSound = try container.decodeIfPresent(Bool.self, forKey: .playWakeWordSound) ?? playWakeWordSound
        playProcessingSound = try container.decodeIfPresent(Bool.self, forKey: .playProcessingSound) ?? playProcessingSound
        playReadyForWakeWordSound = try container.decodeIfPresent(Bool.self, forKey: .playReadyForWakeWordSound) ?? playReadyForWakeWordSound
        micGain = try container.decodeIfPresent(Double.self, forKey: .micGain) ?? micGain
        noiseSuppressionLevel = try container.decodeIfPresent(Int.self, forKey: .noiseSuppressionLevel) ?? noiseSuppressionLevel
        autoGainDBFS = try container.decodeIfPresent(Int.self, forKey: .autoGainDBFS) ?? autoGainDBFS
    }
}
