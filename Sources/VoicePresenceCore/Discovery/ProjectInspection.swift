import Foundation

/// Tout ce que l'app sait d'un projet, étages 1 à 3 réunis.
///
/// Type valeur immuable à une exception près : ``audioAnalysis``, renseignée
/// après coup quand l'étage 3 tourne. Le reste ne change jamais après
/// construction, ce qui rend le partage entre tâches sûr sans verrou.
public struct ProjectInspection: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let alternative: String
    /// Verdict des étages 1 et 2, avant toute analyse audio.
    public let baseVerdict: Verdict
    public let analysis: VoiceBusAnalysis
    /// Nombre de fichiers dans `Media/Audio Files` — comptage d'entrées, sans décodage.
    public let audioFileCount: Int
    public let failure: String?
    /// Étage 3, `nil` tant qu'il n'a pas tourné sur ce projet.
    public var audioAnalysis: AudioAnalysisReport?

    public init(id: UUID = UUID(),
                name: String,
                url: URL,
                alternative: String,
                baseVerdict: Verdict,
                analysis: VoiceBusAnalysis,
                audioFileCount: Int,
                failure: String? = nil,
                audioAnalysis: AudioAnalysisReport? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.alternative = alternative
        self.baseVerdict = baseVerdict
        self.analysis = analysis
        self.audioFileCount = audioFileCount
        self.failure = failure
        self.audioAnalysis = audioAnalysis
    }

    /// Verdict à afficher : révisé par l'étage 3 s'il a tourné.
    public var verdict: Verdict {
        guard let report = audioAnalysis else { return baseVerdict }
        return VerdictPolicy.revised(baseVerdict, with: report)
    }

    public var busLabel: String {
        analysis.busNames.isEmpty ? "—" : analysis.busNames.joined(separator: ", ")
    }
    public var linkedChannelCount: Int { analysis.linkedChannels.count }
    public var channelsWithAudio: Int { analysis.channelsWithAudio }
    public var firmRegions: Int { analysis.firmRegionsOnLinkedChannels }
    public var ambiguousRegions: Int { analysis.ambiguousRegions }

    /// Vrai quand décoder l'audio apporterait une information.
    public var needsAudioAnalysis: Bool {
        audioAnalysis == nil && baseVerdict.benefitsFromAudioAnalysis
    }

    public var audioNote: String? { audioAnalysis?.note }
}

/// Inspecte un projet : étage 1 (binaire) et étage 2 (inventaire disque).
///
/// Dépendances injectées pour que les tests puissent substituer la découverte et
/// l'audio sans toucher au disque réel.
public struct ProjectInspector: Sendable {
    private let locator: ProjectLocator
    private let audioAnalyzer: any AudioAnalyzing

    public init(locator: ProjectLocator = ProjectLocator(),
                audioAnalyzer: any AudioAnalyzing = SystemAudioAnalyzer()) {
        self.locator = locator
        self.audioAnalyzer = audioAnalyzer
    }

    public func inspect(project url: URL, busName: String) -> ProjectInspection {
        let name = url.deletingPathExtension().lastPathComponent
        // Comptage de fichiers : une lecture de dossier, aucun décodage.
        let audioFileCount = audioAnalyzer.audioFiles(in: url).count

        guard let location = locator.latestProjectData(in: url) else {
            Log.scan.notice("Projet sans ProjectData exploitable")
            return ProjectInspection(name: name, url: url, alternative: "—",
                                     baseVerdict: .unreadable, analysis: .empty,
                                     audioFileCount: audioFileCount,
                                     failure: "Aucun ProjectData trouvé")
        }

        do {
            let analysis = try VoiceBusAnalyzer.analyze(fileAt: location.url, busName: busName)
            return ProjectInspection(name: name, url: url,
                                     alternative: location.alternative,
                                     baseVerdict: VerdictPolicy.verdict(for: analysis,
                                                                        audioFileCount: audioFileCount),
                                     analysis: analysis,
                                     audioFileCount: audioFileCount)
        } catch {
            Log.scan.error("Lecture du ProjectData impossible : \(error.localizedDescription, privacy: .public)")
            return ProjectInspection(name: name, url: url,
                                     alternative: location.alternative,
                                     baseVerdict: .unreadable, analysis: .empty,
                                     audioFileCount: audioFileCount,
                                     failure: error.localizedDescription)
        }
    }
}
