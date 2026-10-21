import Foundation

/// Conclusion pour un projet, et son degré de certitude.
///
/// Les trois étages d'analyse sont de coûts très différents :
///
/// | Étage | Quoi                        | Coût                    |
/// |-------|-----------------------------|-------------------------|
/// | 1     | binaire `ProjectData`       | ~10 ms par projet       |
/// | 2     | inventaire disque           | négligeable             |
/// | 3     | décodage + classification   | ~1 s par fichier audio  |
///
/// L'étage 3 ne tourne que sur ``undecidable`` — le seul verdict qu'il puisse
/// faire évoluer. Les autres sont déjà tranchés par un raisonnement sûr.
public enum Verdict: String, CaseIterable, Sendable {

    /// Au moins une région rattachée de façon certaine à un canal du bus.
    case busWithAudio = "Bus + audio"

    /// Régions rattachées au bus, mais sans pouvoir trancher le canal exact.
    case busProbableAudio = "Bus + audio (probable)"

    /// Des canaux alimentent le bus, aucune région ne leur est rattachable, et
    /// pourtant le projet contient des régions **et** des fichiers audio.
    /// L'appariement par nom a donc pu échouer — c'est le seul cas où décoder
    /// l'audio apporte une information.
    case undecidable = "Indécidable"

    /// Des canaux alimentent le bus et rien ne peut y être rattaché. Quand le
    /// projet n'a aucun fichier audio, cette conclusion est certaine : s'il n'y
    /// a aucun audio dans le projet, il n'y en a pas davantage sur le bus.
    case busNoAudio = "Bus sans audio"

    /// Le bus existe, aucun canal ne route dessus.
    case busOrphan = "Bus orphelin"

    /// Aucun canal ne porte le nom cherché.
    case noBus = "Pas de bus"

    /// Projet illisible : pas de `ProjectData`, ou lecture impossible.
    case unreadable = "Illisible"

    /// Ordre d'affichage : les cas qui demandent une action en tête.
    public var sortRank: Int {
        switch self {
        case .undecidable: 0
        case .busNoAudio: 1
        case .busProbableAudio: 2
        case .busOrphan: 3
        case .busWithAudio: 4
        case .noBus: 5
        case .unreadable: 6
        }
    }

    /// Seul verdict que l'étage 3 peut faire évoluer.
    public var benefitsFromAudioAnalysis: Bool { self == .undecidable }

    /// Explication affichable, pour que l'utilisateur sache sur quoi repose la
    /// conclusion plutôt que de devoir la croire.
    public var rationale: String {
        switch self {
        case .busWithAudio:
            "Au moins une région audio est rattachée de façon certaine à un canal routé vers ce bus."
        case .busProbableAudio:
            "Des régions se rattachent au bus, mais plusieurs canaux sont à égalité : impossible de désigner lequel les porte."
        case .undecidable:
            "Des canaux alimentent le bus, le projet contient des régions et des fichiers audio, mais aucun nom ne concorde. L'analyse audio peut trancher."
        case .busNoAudio:
            "Des canaux alimentent le bus, et rien dans le projet ne peut leur être rattaché."
        case .busOrphan:
            "Le bus existe dans le mixeur, mais aucun canal n'y envoie son signal."
        case .noBus:
            "Aucun canal du mixeur ne porte le nom cherché."
        case .unreadable:
            "Le ProjectData est absent ou illisible."
        }
    }
}

/// Décide du verdict à partir de l'analyse et de l'inventaire disque.
///
/// Isolé dans son propre type : c'est la règle métier, elle doit être lisible et
/// testable sans toucher au disque ni au binaire.
public enum VerdictPolicy {

    public static func verdict(for analysis: VoiceBusAnalysis, audioFileCount: Int) -> Verdict {
        guard analysis.hasBus else { return .noBus }
        guard !analysis.linkedChannels.isEmpty else { return .busOrphan }
        if analysis.linkedChannels.contains(where: \.hasAudio) { return .busWithAudio }
        if analysis.ambiguousRegions > 0 { return .busProbableAudio }
        // Rien de rattachable. Si le projet contient malgré tout des régions et
        // des fichiers, c'est l'appariement par nom qui a pu échouer, pas
        // forcément l'audio qui manque.
        if analysis.totalRegions > 0, audioFileCount > 0 { return .undecidable }
        return .busNoAudio
    }

    /// Révise le verdict à la lumière de l'étage 3.
    ///
    /// Le silence est une preuve : un projet dont tous les fichiers sont muets
    /// n'a pas d'audio, point. La présence de voix, elle, ne prouve pas le
    /// rattachement au bus — d'où `busProbableAudio` et non `busWithAudio`.
    public static func revised(_ verdict: Verdict, with report: AudioAnalysisReport) -> Verdict {
        guard verdict.benefitsFromAudioAnalysis else { return verdict }
        if report.files.isEmpty { return .busNoAudio }
        if report.containsVocal { return .busProbableAudio }
        if !report.containsSignal { return .busNoAudio }
        return verdict
    }
}
