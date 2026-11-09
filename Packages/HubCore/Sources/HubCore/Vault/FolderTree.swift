import Foundation

/// Ein Ordner im Vault mit seinen Unterordnern – so wie im Dateiexplorer von Obsidian.
public struct FolderNode: Identifiable, Sendable, Hashable {
    public let path: String
    public var children: [FolderNode]

    public var id: String { path }
    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
    public var depth: Int { path.split(separator: "/").count - 1 }

    public init(path: String, children: [FolderNode] = []) {
        self.path = path
        self.children = children
    }
}

public enum FolderTree {
    /// Baut aus relativen Ordnerpfaden einen Baum. Fehlende Elternordner werden ergänzt.
    /// - Parameter topLevelOrder: Diese Ordner stehen oben in genau dieser Reihenfolge, der Rest alphabetisch.
    public static func build(_ paths: [String], topLevelOrder: [String] = []) -> [FolderNode] {
        var all = Set<String>()
        for path in paths {
            let components = path.split(separator: "/")
            for length in 1...max(components.count, 1) where !components.isEmpty {
                all.insert(components.prefix(length).joined(separator: "/"))
            }
        }

        var childrenByParent: [String: [String]] = [:]
        for path in all {
            let parent = path.split(separator: "/").dropLast().joined(separator: "/")
            childrenByParent[parent, default: []].append(path)
        }

        func node(_ path: String) -> FolderNode {
            let children = (childrenByParent[path] ?? []).sorted(by: alphabetical).map(node)
            return FolderNode(path: path, children: children)
        }

        let order = topLevelOrder.map { $0.lowercased() }
        let top = (childrenByParent[""] ?? []).sorted { lhs, rhs in
            let l = order.firstIndex(of: lhs.lowercased()) ?? Int.max
            let r = order.firstIndex(of: rhs.lowercased()) ?? Int.max
            return l != r ? l < r : alphabetical(lhs, rhs)
        }
        return top.map(node)
    }

    /// Alle Ordner in Baum-Reihenfolge, z. B. für einen Picker.
    public static func flatten(_ nodes: [FolderNode]) -> [FolderNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }

    private static func alphabetical(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
