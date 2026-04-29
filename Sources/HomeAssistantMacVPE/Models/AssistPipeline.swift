import Foundation

struct AssistPipeline: Identifiable, Hashable {
    let id: String
    let name: String
    let language: String?

    var displayName: String {
        if let language, !language.isEmpty {
            return "\(name) (\(language))"
        }
        return name
    }
}
