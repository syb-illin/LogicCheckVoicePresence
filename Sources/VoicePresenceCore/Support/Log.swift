import Foundation
import os

/// Journalisation unifiée.
///
/// `os.Logger` plutôt que `print` : les messages partent dans le sous-système
/// unifié de macOS, donc consultables dans Console.app ou via
/// `log stream --predicate 'subsystem == "io.github.sybillin.LogicCheckVoicePresence"'`
/// sans que l'app paie le coût de la mise en forme quand personne n'écoute.
///
/// Les chaînes interpolées sont marquées `privacy: .public` seulement là où
/// elles ne contiennent pas de données personnelles. Les chemins de fichiers de
/// l'utilisateur restent privés par défaut : ils n'apparaissent pas dans les
/// journaux exportés.
public enum Log {
    public static let subsystem = "io.github.sybillin.LogicCheckVoicePresence"

    /// Découverte des projets sur le disque.
    public static let discovery = Logger(subsystem: subsystem, category: "discovery")
    /// Décodage du binaire ProjectData.
    public static let parsing = Logger(subsystem: subsystem, category: "parsing")
    /// Graphe de routage et attribution des régions.
    public static let routing = Logger(subsystem: subsystem, category: "routing")
    /// Étage 3 : décodage et classification audio.
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    /// Orchestration du scan.
    public static let scan = Logger(subsystem: subsystem, category: "scan")
    /// Vérification de mise à jour.
    public static let updates = Logger(subsystem: subsystem, category: "updates")
    /// Interface.
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Pour les mesures de performance dans Instruments.
    public static let signposter = OSSignposter(subsystem: subsystem, category: "performance")
}
