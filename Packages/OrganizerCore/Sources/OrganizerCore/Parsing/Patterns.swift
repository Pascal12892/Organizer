import Foundation

/// Alle regulären Ausdrücke an einer Stelle, einmal angelegt.
/// Swift kompiliert ein Regex-Literal beim ersten Gebrauch – steht es in einer Funktion,
/// passiert das bei jedem Aufruf neu. Für Tausende Zeilen pro Scan war das der größte Zeitfresser.
enum Patterns {
    nonisolated(unsafe) static let taskLine = #/(\s*(?:[-*+]|\d+[.)])\s+\[(.)\]\s?)(.*)/#
    nonisolated(unsafe) static let isoDate = #/\d{4}-\d{2}-\d{2}/#
    nonisolated(unsafe) static let trailingTaskTokens = #/(?:\s+(?:#[\p{L}\p{N}_\/-]+|✅\s*\d{4}-\d{2}-\d{2}|\^[A-Za-z0-9-]+))+\s*$/#
    nonisolated(unsafe) static let blockID = #/\s+\^[A-Za-z0-9-]+\s*$/#
    nonisolated(unsafe) static let fieldKey = #/[\p{L}\p{N}_-]+/#
    nonisolated(unsafe) static let wikiLink = #/!?\[\[([^\[\]|]+?)(?:\|([^\[\]]+?))?\]\]/#
    nonisolated(unsafe) static let excerptPrefix = #/(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX/-]\]\s+)?|\d+[.)]\s+(?:\[[ xX/-]\]\s+)?)+/#
    nonisolated(unsafe) static let excerptWikiLink = #/!?\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/#
    nonisolated(unsafe) static let markdownLink = #/!?\[([^\]]*)\]\([^)]*\)/#
}
