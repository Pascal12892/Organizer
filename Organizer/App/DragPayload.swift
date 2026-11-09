import Foundation
import UniformTypeIdentifiers

/// Inhalte, die innerhalb von Organizer gezogen werden. Als Text mit Präfix,
/// damit sie sich von beliebigem Text unterscheiden lassen.
nonisolated enum DragPayload {
    static let taskPrefix = "organizer-task:"
    static let notePrefix = "organizer-note:"

    static func task(_ id: String) -> String { taskPrefix + id }
    static func note(_ relativePath: String) -> String { notePrefix + relativePath }

    static func taskID(from string: String) -> String? {
        string.hasPrefix(taskPrefix) ? String(string.dropFirst(taskPrefix.count)) : nil
    }

    static func notePath(from string: String) -> String? {
        string.hasPrefix(notePrefix) ? String(string.dropFirst(notePrefix.count)) : nil
    }
}
