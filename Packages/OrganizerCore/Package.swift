// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OrganizerCore",
    defaultLocalization: "de",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "OrganizerCore", targets: ["OrganizerCore"]),
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
        .testTarget(name: "OrganizerCoreTests", dependencies: ["OrganizerCore"]),
    ]
)
