// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "LogicCheckVoicePresence",
    // Cible de déploiement, distincte de la version du langage : l'app est
    // compilée avec Swift 6 mais tourne depuis macOS 14 (Sonoma).
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
    ],
    // Mode langage 6 : la sûreté face aux accès concurrents est vérifiée à la
    // compilation et traitée en erreur, pas en avertissement. C'est le mode qui
    // correspond à une app dont le scan est parallèle.
    swiftLanguageModes: [.v6]
)
