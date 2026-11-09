import Foundation
import OrganizerCore

/// MCP-Server für Organizer (JSON-RPC 2.0 über stdin/stdout, eine Nachricht pro Zeile).
///
/// Aufruf: `organizer-mcp --vault <Pfad> [--areas auto|Uni,Arbeit,…] [--tasks central|folder]`
///
/// Claude Desktop bzw. Claude Code starten das Programm selbst. Auf stdout steht ausschließlich
/// das Protokoll; Hinweise gehen an stderr.
@main
struct OrganizerMCP {
    static let supportedVersions = ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"]

    @MainActor
    static func main() async {
        let options: Options
        do {
            options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            log("organizer-mcp: \(error.localizedDescription)")
            log("Aufruf: organizer-mcp --vault <Pfad zum Obsidian-Vault> [--areas auto|Uni,Arbeit] [--tasks central|folder]")
            exit(64)
        }
        let tools = ToolBox(options: options)
        log("organizer-mcp: Vault \(options.vault.path(percentEncoded: false))")

        do {
            for try await line in FileHandle.standardInput.bytes.lines {
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                guard let message = try? JSONValue.parse(line) else {
                    send(["jsonrpc": "2.0", "id": .null, "error": ["code": -32700, "message": "Parse error"]])
                    continue
                }
                if let response = await handle(message, tools: tools) { send(response) }
            }
        } catch {
            log("organizer-mcp: Eingabe beendet: \(error.localizedDescription)")
        }
    }

    @MainActor
    static func handle(_ message: JSONValue, tools: ToolBox) async -> JSONValue? {
        let id = message["id"]
        let method = message["method"]?.stringValue ?? ""
        let params = message["params"] ?? .object([:])

        func result(_ value: JSONValue) -> JSONValue? {
            guard let id else { return nil } // Benachrichtigung: keine Antwort
            return ["jsonrpc": "2.0", "id": id, "result": value]
        }
        func error(_ code: Int, _ text: String) -> JSONValue? {
            guard let id else { return nil }
            return ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(text)]]
        }

        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.stringValue ?? ""
            let version = supportedVersions.contains(requested) ? requested : supportedVersions[2]
            return result([
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "organizer", "title": "Organizer", "version": "0.8"],
                "instructions": .string(ToolBox.instructions),
            ])
        case "ping":
            return result([:])
        case "tools/list":
            return result(["tools": .array(ToolBox.definitions.map(\.mcpDefinition))])
        case "tools/call":
            guard let name = params["name"]?.stringValue else { return error(-32602, "Werkzeugname fehlt.") }
            let arguments = params["arguments"] ?? .object([:])
            do {
                let output = try await tools.call(name, arguments: arguments)
                return result(["content": [["type": "text", "text": .string(output.jsonString)]], "isError": false])
            } catch {
                // Fehler beim Ausführen gehen als Ergebnis zurück, damit Claude reagieren kann.
                return result(["content": [["type": "text", "text": .string(error.localizedDescription)]], "isError": true])
            }
        default:
            if method.hasPrefix("notifications/") { return nil }
            return error(-32601, "Unbekannte Methode: \(method)")
        }
    }

    static func send(_ message: JSONValue) {
        guard var data = try? message.encoded() else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    static func log(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}

/// Kommandozeilen-Optionen.
struct Options {
    enum TaskStorage { case central, perFolder }

    let vault: URL
    let layout: VaultLayout
    let taskStorage: TaskStorage

    struct Problem: LocalizedError {
        let errorDescription: String?
    }

    init(arguments: [String]) throws {
        var vault: String?
        var areas = "auto"
        var tasks = "central"
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--vault": vault = iterator.next()
            case "--areas": areas = iterator.next() ?? "auto"
            case "--tasks": tasks = iterator.next() ?? "central"
            default: throw Problem(errorDescription: "Unbekannte Option „\(argument)“.")
            }
        }
        guard let vault, !vault.isEmpty else { throw Problem(errorDescription: "--vault fehlt.") }
        let url = URL(filePath: (vault as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Problem(errorDescription: "Vault-Ordner nicht gefunden: \(url.path(percentEncoded: false))")
        }
        self.vault = url
        self.layout = areas == "auto"
            ? VaultLayout(areas: [], automaticAreas: true)
            : VaultLayout(areas: areas.split(separator: ",").map(String.init))
        self.taskStorage = tasks == "folder" ? .perFolder : .central
    }
}
