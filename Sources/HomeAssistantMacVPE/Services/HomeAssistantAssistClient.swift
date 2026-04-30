import Foundation

@MainActor
final class HomeAssistantAssistClient {
    var onLog: ((String) -> Void)?
    var onState: ((AssistantState) -> Void)?
    var onBinaryHandler: ((UInt8) -> Void)?
    var onWakeWordDetected: (() -> Void)?
    var onPipelineError: ((String, String) -> Void)?
    var onTTSURL: ((URL) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var baseURL: URL?
    private var nextID = 1
    private var pendingResults: [Int: CheckedContinuation<Any, Error>] = [:]
    private var lastAudioSendTask: Task<Void, Never>?
    private(set) var binaryHandlerID: UInt8?

    var isConnected: Bool {
        task != nil
    }

    func connect(homeAssistantURL: String, token: String) async throws {
        if task != nil {
            return
        }

        guard let base = URL(string: homeAssistantURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw AssistClientError.invalidURL
        }

        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.scheme = base.scheme == "https" ? "wss" : "ws"
        components?.path = "/api/websocket"
        guard let websocketURL = components?.url else {
            throw AssistClientError.invalidURL
        }

        baseURL = base
        onState?(.connecting)
        onLog?("Connecting to \(websocketURL.host ?? "Home Assistant")")

        let socket = URLSession.shared.webSocketTask(with: websocketURL)
        socket.resume()
        task = socket

        let authRequired = try await receiveJSON()
        guard authRequired["type"] as? String == "auth_required" else {
            throw AssistClientError.authenticationFailed
        }

        try await sendJSON([
            "type": "auth",
            "access_token": token
        ])

        let authResponse = try await receiveJSON()
        guard authResponse["type"] as? String == "auth_ok" else {
            throw AssistClientError.authenticationFailed
        }

        onLog?("Authenticated with Home Assistant")
        receiveTask = Task { [weak self] in
            await self?.receiveLoop()
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        binaryHandlerID = nil
        lastAudioSendTask?.cancel()
        lastAudioSendTask = nil
        pendingResults.values.forEach { $0.resume(throwing: AssistClientError.notConnected) }
        pendingResults.removeAll()
        onState?(.idle)
    }

    func listPipelines() async throws -> (pipelines: [AssistPipeline], preferredPipelineID: String?) {
        guard task != nil else {
            throw AssistClientError.notConnected
        }

        let result = try await sendCommand([
            "type": "assist_pipeline/pipeline/list"
        ])

        guard let dictionary = result as? [String: Any] else {
            throw AssistClientError.invalidMessage
        }

        let preferred = dictionary["preferred_pipeline"] as? String
        let pipelines = (dictionary["pipelines"] as? [[String: Any]] ?? []).compactMap { raw -> AssistPipeline? in
            guard let id = raw["id"] as? String else {
                return nil
            }
            let name = raw["name"] as? String ?? id
            let language = (raw["language"] as? String) ?? (raw["conversation_language"] as? String)
            return AssistPipeline(id: id, name: name, language: language)
        }
        return (pipelines, preferred)
    }

    func startPipeline(settings: AppSettings, sampleRate: Double) async throws {
        guard task != nil else {
            throw AssistClientError.notConnected
        }

        binaryHandlerID = nil
        lastAudioSendTask?.cancel()
        lastAudioSendTask = nil
        let startStage = settings.useWakeWord ? "wake_word" : "stt"
        var input: [String: Any] = [
            "sample_rate": Int(sampleRate)
        ]

        let noiseSuppressionLevel = max(0, min(4, settings.noiseSuppressionLevel))
        let autoGainDBFS = max(0, min(31, settings.autoGainDBFS))
        if noiseSuppressionLevel > 0 {
            input["noise_suppression_level"] = noiseSuppressionLevel
        }
        if autoGainDBFS > 0 {
            input["auto_gain_dbfs"] = autoGainDBFS
        }

        if settings.useWakeWord {
            input["timeout"] = 30
        }

        var command: [String: Any] = [
            "id": nextCommandID(),
            "type": "assist_pipeline/run",
            "start_stage": startStage,
            "end_stage": "tts",
            "input": input,
            "timeout": 300
        ]

        let pipeline = settings.pipelineID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pipeline.isEmpty {
            command["pipeline"] = pipeline
        }

        try await sendJSON(command)
        onLog?("Started Assist pipeline from \(startStage)")
    }

    func sendAudioChunk(_ data: Data) {
        guard let task,
              let handlerID = binaryHandlerID else {
            return
        }
        var payload = Data([handlerID])
        payload.append(data)

        let previousSend = lastAudioSendTask
        lastAudioSendTask = Task { [weak self] in
            await previousSend?.value
            guard !Task.isCancelled else {
                return
            }

            do {
                try await task.send(.data(payload))
            } catch {
                await MainActor.run {
                    self?.onLog?("Audio stream send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func finishAudio() async {
        guard let task,
              let handlerID = binaryHandlerID else {
            return
        }
        await lastAudioSendTask?.value
        try? await task.send(.data(Data([handlerID])))
        lastAudioSendTask = nil
    }

    private func receiveLoop() async {
        while !Task.isCancelled {
            do {
                let json = try await receiveJSON()
                handle(json)
            } catch {
                if !Task.isCancelled {
                    onLog?("Home Assistant connection closed: \(error.localizedDescription)")
                    onState?(.error(error.localizedDescription))
                    disconnect()
                }
                return
            }
        }
    }

    private func handle(_ json: [String: Any]) {
        if json["type"] as? String == "result",
           let id = json["id"] as? Int,
           let continuation = pendingResults.removeValue(forKey: id) {
            if json["success"] as? Bool == true {
                continuation.resume(returning: json["result"] ?? [:])
            } else {
                let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown WebSocket command error"
                continuation.resume(throwing: AssistClientError.commandFailed(message))
            }
            return
        }

        if json["type"] as? String == "result",
           let success = json["success"] as? Bool,
           !success {
            let error = (json["error"] as? [String: Any])?["message"] as? String ?? "Unknown WebSocket command error"
            onState?(.error(error))
            onLog?("Assist command failed: \(error)")
            return
        }

        guard json["type"] as? String == "event",
              let event = json["event"] as? [String: Any],
              let eventType = event["type"] as? String
        else {
            return
        }

        let data = event["data"] as? [String: Any] ?? [:]
        switch eventType {
        case "run-start":
            if let runnerData = data["runner_data"] as? [String: Any],
               let handler = runnerData["stt_binary_handler_id"] as? Int,
               let handlerID = UInt8(exactly: handler) {
                binaryHandlerID = handlerID
                onBinaryHandler?(handlerID)
            }
        case "wake_word-start":
            onState?(.waitingForWakeWord)
            onLog?("Home Assistant is listening for the wake word")
        case "wake_word-end":
            onLog?("Wake word detected")
            onWakeWordDetected?()
            onState?(.listening)
        case "stt-start":
            onState?(.listening)
            onLog?("Speech capture started")
            if let metadata = data["metadata"] as? [String: Any] {
                onLog?("STT expects \(metadataDescription(metadata))")
            }
        case "stt-end":
            onState?(.thinking)
        case "intent-start":
            onState?(.thinking)
        case "tts-start":
            onState?(.speaking)
        case "tts-end", "run-end":
            if let url = ttsURL(from: data) {
                onTTSURL?(url)
            }
            if eventType == "run-end" {
                binaryHandlerID = nil
                lastAudioSendTask?.cancel()
                lastAudioSendTask = nil
                onState?(.idle)
            }
        case "error":
            let code = data["code"] as? String ?? "unknown"
            let message = data["message"] as? String ?? "Assist pipeline error"
            binaryHandlerID = nil
            lastAudioSendTask?.cancel()
            lastAudioSendTask = nil
            onPipelineError?(code, message)
            onLog?(message)
        default:
            break
        }
    }

    private func ttsURL(from data: [String: Any]) -> URL? {
        let ttsOutput = data["tts_output"] as? [String: Any]
        guard let rawURL = (ttsOutput?["url"] as? String) ?? (data["url"] as? String) else {
            return nil
        }
        if let absolute = URL(string: rawURL), absolute.scheme != nil {
            return absolute
        }
        return URL(string: rawURL, relativeTo: baseURL)?.absoluteURL
    }

    private func metadataDescription(_ metadata: [String: Any]) -> String {
        let sampleRate = metadata["sample_rate"] ?? "?"
        let bitRate = metadata["bit_rate"] ?? "?"
        let channel = metadata["channel"] ?? "?"
        let codec = metadata["codec"] ?? "?"
        return "\(sampleRate) Hz, \(bitRate)-bit, \(channel) channel, \(codec)"
    }

    private func receiveJSON() async throws -> [String: Any] {
        guard let task else {
            throw AssistClientError.notConnected
        }
        let message = try await task.receive()
        switch message {
        case let .string(text):
            return try decodeJSON(Data(text.utf8))
        case let .data(data):
            return try decodeJSON(data)
        @unknown default:
            throw AssistClientError.invalidMessage
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let task else {
            throw AssistClientError.notConnected
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw AssistClientError.invalidMessage
        }
        try await task.send(.string(text))
    }

    private func sendCommand(_ object: [String: Any]) async throws -> Any {
        var command = object
        let id = nextCommandID()
        command["id"] = id

        return try await withCheckedThrowingContinuation { continuation in
            pendingResults[id] = continuation
            Task { @MainActor in
                do {
                    try await self.sendJSON(command)
                } catch {
                    self.pendingResults.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func decodeJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AssistClientError.invalidMessage
        }
        return json
    }

    private func nextCommandID() -> Int {
        defer { nextID += 1 }
        return nextID
    }
}

enum AssistClientError: LocalizedError {
    case invalidURL
    case authenticationFailed
    case invalidMessage
    case notConnected
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The Home Assistant URL is not valid."
        case .authenticationFailed:
            "Home Assistant rejected the access token."
        case .invalidMessage:
            "Home Assistant returned an unexpected WebSocket message."
        case .notConnected:
            "The Home Assistant WebSocket is not connected."
        case let .commandFailed(message):
            message
        }
    }
}
