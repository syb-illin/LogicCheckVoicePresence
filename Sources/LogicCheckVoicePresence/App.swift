import SwiftUI
import VoicePresenceCore

@main
struct LogicCheckVoicePresenceApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                // Remplace le panneau « À propos » standard, qui n'afficherait
                // que les clés d'Info.plist, par la fenêtre de l'app.
                Button("À propos de \(AppInfo.name)") {
                    NSApp.sendAction(Selector(("showAboutWindow:")), to: nil, from: nil)
                }
            }
            CommandGroup(after: .appInfo) {
                Link("Code source", destination: AppInfo.repositoryURL)
                Link("Signaler un problème", destination: AppInfo.issuesURL)
            }
        }
    }
}
