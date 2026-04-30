import CoreAudio
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            saveSettings()
        }
    }
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var pipelines: [AssistPipeline] = []
    @Published private(set) var isLoadingPipelines = false
    @Published private(set) var state: AssistantState = .idle
    @Published private(set) var logs: [String] = []

    private let settingsURL: URL
    private let audioDeviceManager = AudioDeviceManager()
    private let audioCapture = AudioCaptureService()
    private let playback = SpeechPlaybackService()
    private lazy var assistClient = HomeAssistantAssistClient()
    private var shouldKeepSessionRunning = false
    private var wakeWordRestartTask: Task<Void, Never>?
    private var didReachSpeechInCurrentRun = false
    private var currentPipelineUsesWakeWord = false
    private var isPlayingAssistantResponse = false
    private var shouldContinueConversationAfterPlayback = false
    private var continuedConversationID: String?

    var isSessionActive: Bool {
        shouldKeepSessionRunning || audioCapture.isCapturing || assistClient.binaryHandlerID != nil
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "HomeAssistantMacVPE", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        settingsURL = support.appending(path: "settings.json")
        settings = Self.loadSettings(from: settingsURL)
        refreshAudioDevices()
    }

    func start() async {
        refreshAudioDevices()
        applyLoginItemPreference()
        if settings.hasHomeAssistantConnection {
            await refreshPipelines()
            if settings.startListeningOnLaunch, !isSessionActive {
                await startSession()
            }
        }
    }

    func refreshAudioDevices() {
        inputDevices = audioDeviceManager.inputDevices()
        outputDevices = audioDeviceManager.outputDevices()

        if settings.selectedInputUID.isEmpty, let device = inputDevices.first {
            settings.selectedInputUID = device.uid
        }
        if settings.selectedOutputUID.isEmpty, let device = outputDevices.first {
            settings.selectedOutputUID = device.uid
        }
    }

    func updateLoginItem(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        applyLoginItemPreference()
    }

    func toggleSession() async {
        if isSessionActive {
            await stopSession()
        } else {
            await startSession()
        }
    }

    func startSession() async {
        guard settings.hasHomeAssistantConnection else {
            state = .error("Add your Home Assistant URL and access token first.")
            return
        }

        do {
            shouldKeepSessionRunning = true
            didReachSpeechInCurrentRun = false
            currentPipelineUsesWakeWord = settings.useWakeWord
            shouldContinueConversationAfterPlayback = false
            continuedConversationID = nil
            configureAssistCallbacks()
            try await assistClient.connect(homeAssistantURL: settings.homeAssistantURL, token: settings.accessToken)
            try await assistClient.startPipeline(settings: settings, sampleRate: selectedInputSampleRate())
        } catch {
            shouldKeepSessionRunning = false
            state = .error(error.localizedDescription)
            log(error.localizedDescription)
        }
    }

    func stopSession() async {
        shouldKeepSessionRunning = false
        wakeWordRestartTask?.cancel()
        wakeWordRestartTask = nil
        shouldContinueConversationAfterPlayback = false
        continuedConversationID = nil
        isPlayingAssistantResponse = false
        audioCapture.stop()
        playback.stopResponsePlayback()
        await assistClient.finishAudio()
        assistClient.disconnect()
        state = .idle
        log("Stopped listening")
    }

    func refreshPipelines() async {
        guard settings.hasHomeAssistantConnection else {
            state = .error("Add your Home Assistant URL and access token first.")
            return
        }

        isLoadingPipelines = true
        defer { isLoadingPipelines = false }

        do {
            configureAssistCallbacks()
            if assistClient.isConnected && !isSessionActive {
                assistClient.disconnect()
            }
            try await assistClient.connect(homeAssistantURL: settings.homeAssistantURL, token: settings.accessToken)
            let response = try await assistClient.listPipelines()
            pipelines = response.pipelines
            if settings.pipelineID.isEmpty {
                settings.pipelineID = response.preferredPipelineID ?? response.pipelines.first?.id ?? ""
            } else if !response.pipelines.contains(where: { $0.id == settings.pipelineID }) {
                settings.pipelineID = response.preferredPipelineID ?? response.pipelines.first?.id ?? ""
            }
            if let selectedPipeline = pipelines.first(where: { $0.id == settings.pipelineID }) {
                log("Selected Assist pipeline: \(selectedPipeline.displayName)")
            }
            log("Loaded \(pipelines.count) Assist pipeline\(pipelines.count == 1 ? "" : "s")")
        } catch {
            state = .error(error.localizedDescription)
            log("Unable to load Assist pipelines: \(error.localizedDescription)")
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    func clampedDoubleBinding(_ keyPath: WritableKeyPath<AppSettings, Double>, range: ClosedRange<Double>) -> Binding<Double> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    func integerSliderBinding(_ keyPath: WritableKeyPath<AppSettings, Int>, range: ClosedRange<Int>) -> Binding<Double> {
        Binding(
            get: { Double(self.settings[keyPath: keyPath]) },
            set: { self.settings[keyPath: keyPath] = min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }
        )
    }

    private func configureAssistCallbacks() {
        assistClient.onLog = { [weak self] message in
            self?.log(message)
        }
        assistClient.onState = { [weak self] newState in
            guard let self else { return }
            if self.state == .listening,
               newState == .thinking,
               self.settings.playProcessingSound {
                self.playback.playProcessingSound(outputUID: self.selectedOutputUID())
            }

            if case .idle = newState,
               self.shouldKeepSessionRunning,
               self.settings.useWakeWord {
                if self.shouldContinueConversationAfterPlayback {
                    if self.isPlayingAssistantResponse {
                        self.state = .speaking
                    } else {
                        Task { await self.startContinuedConversationIfNeeded() }
                    }
                    return
                }

                if self.didReachSpeechInCurrentRun,
                   self.settings.playReadyForWakeWordSound {
                    self.playback.playReadyForWakeWordSound(outputUID: self.selectedOutputUID())
                }
                self.didReachSpeechInCurrentRun = false
                self.state = .waitingForWakeWord
                self.scheduleWakeWordRestart(reason: "Restarting wake word listener")
            } else {
                self.state = newState
            }
        }
        assistClient.onBinaryHandler = { [weak self] _ in
            guard let self else { return }
            do {
                try self.audioCapture.start(
                    inputDeviceID: self.selectedInputDeviceID(),
                    sampleRate: self.selectedInputSampleRate(),
                    gain: self.settings.micGain,
                    onDiagnostic: { [weak self] message in
                        Task { @MainActor in
                            self?.log(message)
                        }
                    }
                ) { [weak self] chunk in
                    Task { @MainActor in
                        self?.assistClient.sendAudioChunk(chunk)
                    }
                }
                self.state = self.currentPipelineUsesWakeWord ? .waitingForWakeWord : .listening
            } catch {
                self.state = .error(error.localizedDescription)
                self.log(error.localizedDescription)
            }
        }
        assistClient.onWakeWordDetected = { [weak self] in
            guard let self else { return }
            self.didReachSpeechInCurrentRun = true
            if self.playback.pauseResponsePlayback() {
                self.log("Paused playback after wake word")
            }
            if self.settings.playWakeWordSound {
                self.playback.playWakeSound(outputUID: self.selectedOutputUID())
            }
        }
        assistClient.onConversationContinuation = { [weak self] shouldContinue, conversationID in
            guard let self else { return }
            self.shouldContinueConversationAfterPlayback = shouldContinue
            self.continuedConversationID = shouldContinue ? conversationID : nil
        }
        assistClient.onPipelineError = { [weak self] code, message in
            guard let self else { return }
            self.handlePipelineError(code: code, message: message)
        }
        assistClient.onTTSURL = { [weak self] url in
            guard let self else { return }
            self.isPlayingAssistantResponse = true
            Task {
                do {
                    let result = try await self.playback.playDownloadedAudio(from: url, outputUID: self.selectedOutputUID())
                    await self.handleAssistantPlaybackFinished(result)
                } catch {
                    await MainActor.run {
                        self.isPlayingAssistantResponse = false
                        self.shouldContinueConversationAfterPlayback = false
                        self.continuedConversationID = nil
                        self.log("Playback failed: \(error.localizedDescription)")
                        if self.shouldKeepSessionRunning, self.settings.useWakeWord {
                            self.state = .waitingForWakeWord
                            self.scheduleWakeWordRestart(reason: "Restarting wake word listener after playback failure")
                        }
                    }
                }
            }
        }
    }

    private func handleAssistantPlaybackFinished(_ result: ResponsePlaybackResult) async {
        isPlayingAssistantResponse = false

        guard result == .finished,
              shouldContinueConversationAfterPlayback
        else {
            if result == .interrupted {
                shouldContinueConversationAfterPlayback = false
                continuedConversationID = nil
            }
            return
        }

        await startContinuedConversationIfNeeded()
    }

    private func startContinuedConversationIfNeeded() async {
        guard shouldKeepSessionRunning,
              shouldContinueConversationAfterPlayback,
              assistClient.isConnected
        else {
            shouldContinueConversationAfterPlayback = false
            continuedConversationID = nil
            return
        }

        let conversationID = continuedConversationID
        shouldContinueConversationAfterPlayback = false
        continuedConversationID = nil
        didReachSpeechInCurrentRun = false
        currentPipelineUsesWakeWord = false
        state = .listening
        log("Listening for follow-up response")

        do {
            try await assistClient.startPipeline(
                settings: settings,
                sampleRate: selectedInputSampleRate(),
                startStage: .stt,
                conversationID: conversationID
            )
        } catch {
            shouldKeepSessionRunning = false
            state = .error(error.localizedDescription)
            log(error.localizedDescription)
        }
    }

    private func handlePipelineError(code: String, message: String) {
        audioCapture.stop()
        shouldContinueConversationAfterPlayback = false
        continuedConversationID = nil

        guard settings.useWakeWord,
              shouldKeepSessionRunning,
              assistClient.isConnected
        else {
            shouldKeepSessionRunning = false
            state = .error(message)
            return
        }

        state = .waitingForWakeWord
        didReachSpeechInCurrentRun = false
        scheduleWakeWordRestart(reason: "Restarting wake word listener after \(code)")
    }

    private func scheduleWakeWordRestart(reason: String) {
        guard wakeWordRestartTask == nil else {
            return
        }

        log(reason)
        wakeWordRestartTask?.cancel()
        wakeWordRestartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self else {
                return
            }
            self.wakeWordRestartTask = nil

            guard !Task.isCancelled,
                  self.shouldKeepSessionRunning,
                  self.settings.useWakeWord,
                  self.assistClient.isConnected
            else {
                return
            }

            do {
                self.didReachSpeechInCurrentRun = false
                self.currentPipelineUsesWakeWord = self.settings.useWakeWord
                try await self.assistClient.startPipeline(settings: self.settings, sampleRate: self.selectedInputSampleRate())
            } catch {
                self.shouldKeepSessionRunning = false
                self.state = .error(error.localizedDescription)
                self.log(error.localizedDescription)
            }
        }
    }

    private func selectedInputDeviceID() -> AudioDeviceID? {
        audioDeviceManager.deviceID(forUID: settings.selectedInputUID, scope: kAudioObjectPropertyScopeInput)
    }

    private func selectedInputSampleRate() -> Double {
        audioDeviceManager.nominalSampleRate(for: selectedInputDeviceID()) ?? 44_100
    }

    private func selectedOutputUID() -> String? {
        settings.selectedOutputUID.isEmpty ? nil : settings.selectedOutputUID
    }

    private func applyLoginItemPreference() {
        do {
            try LoginItemService.setEnabled(settings.launchAtLogin)
            log(settings.launchAtLogin ? "Enabled launch at login" : "Launch at login disabled")
        } catch {
            log("Launch at login could not be updated: \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        let line = "\(DateFormatting.logTime.string(from: Date()))  \(message)"
        logs.insert(line, at: 0)
        logs = Array(logs.prefix(80))
    }

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        try? data.write(to: settingsURL, options: .atomic)
    }

    private static func loadSettings(from url: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return settings
    }
}
