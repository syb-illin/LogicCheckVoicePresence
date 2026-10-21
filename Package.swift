// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LogicCheckVoicePresence",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoicePresenceCore", targets: ["VoicePresenceCore"]),
        .executable(name: "LogicCheckVoicePresence", targets: ["LogicCheckVoicePresence"]),
    ],
    targets: [
        // Cœur analytique : aucune dépendance SwiftUI, entièrement testable.
        .target(name: "VoicePresenceCore", path: "Sources/VoicePresenceCore"),
        // Interface.
        .executableTarget(name: "LogicCheckVoicePresence",
                          dependencies: ["VoicePresenceCore"],
                          path: "Sources/LogicCheckVoicePresence"),
        .testTarget(name: "VoicePresenceCoreTests",
                    dependencies: ["VoicePresenceCore"],
                    path: "Tests/VoicePresenceCoreTests"),
    ]
)
