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
            // La fenêtre « À propos » est ouverte depuis la barre d'outils, où
            // elle est à portée de clic. On n'ajoute ici que des liens, sans
            // détourner l'élément de menu standard : le faire demanderait de
            // piloter l'état de la vue depuis la barre de menus, pour une
            // duplication sans bénéfice.
            CommandGroup(after: .appInfo) {
                Divider()
                Link("Code source", destination: AppInfo.repositoryURL)
                Link("Signaler un problème", destination: AppInfo.issuesURL)
            }
            CommandGroup(replacing: .newItem) {}   // l'app n'a pas de document
        }
    }
}
