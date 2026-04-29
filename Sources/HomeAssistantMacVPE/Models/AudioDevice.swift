import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: UInt32
    let uid: String
    let name: String
    let isInput: Bool
    let isDefault: Bool

    var displayName: String {
        isDefault ? "\(name) (Default)" : name
    }
}
