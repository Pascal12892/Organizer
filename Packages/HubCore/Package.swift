// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HubCore",
    defaultLocalization: "de",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "HubCore", targets: ["HubCore"]),
    ],
    dependencies: [
        // Apples eigener Markdown-Parser (cmark-gfm). Einzige externe Abhängigkeit:
        // Tabellen, Aufgabenlisten und Codeblöcke kann AttributedString(markdown:) nicht.
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "HubCore",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .testTarget(name: "HubCoreTests", dependencies: ["HubCore"]),
    ]
)
