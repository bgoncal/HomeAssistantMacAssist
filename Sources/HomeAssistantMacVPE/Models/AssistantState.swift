import Foundation

enum AssistantState: Equatable {
    case idle
    case connecting
    case waitingForWakeWord
    case listening
    case thinking
    case speaking
    case error(String)

    var title: String {
        switch self {
        case .idle: "Idle"
        case .connecting: "Connecting"
        case .waitingForWakeWord: "Waiting for wake word"
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case let .error(message): "Error: \(message)"
        }
    }
}
