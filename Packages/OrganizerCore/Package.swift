// swift-tools-version: 6.2
import Foundation
import PackageDescription

/// Info.plist für den MCP-Server (Begründung für den Kalenderzugriff), direkt ins Programm eingebettet.
let mcpInfoPlist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Sources/organizer-mcp/Info.plist").path

let package = Package(
    name: "OrganizerCore",
    defaultLocalization: "de",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OrganizerCore", targets: ["OrganizerCore"]),
        .executable(name: "organizer-mcp", targets: ["organizer-mcp"]),
    ],
    dependencies: [
        // Apples eigener Markdown-Parser (cmark-gfm). Einzige externe Abhängigkeit:
        // Tabellen, Aufgabenlisten und Codeblöcke kann AttributedString(markdown:) nicht.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "OrganizerCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        // MCP-Server: Claude (Desktop-App oder Claude Code, über dein Abo) nutzt damit Vault, Aufgaben und Kalender.
        .executableTarget(
            name: "organizer-mcp",
            dependencies: ["OrganizerCore"],
            exclude: ["Info.plist"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist", "-Xlinker", mcpInfoPlist])]
        ),
        .testTarget(name: "OrganizerCoreTests", dependencies: ["OrganizerCore"]),
    ]
)
