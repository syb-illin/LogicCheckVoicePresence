import Foundation

/// Mesure d'un fichier audio : niveau crête (déterministe) et classification du
/// contenu (probabiliste).
public struct AudioFileMeasurement: Identifiable, Hashable, Sendable {
    public var id: String { fileName }
    public let fileName: String
    public let duration: TimeInterval
    /// Crête en dBFS. `-.infinity` pour un fichier entièrement nul.
    public let peakDB: Float
    public let isSilent: Bool
    /// Libellés renvoyés par le classifieur, les plus probables d'abord.
    public let labels: [ClassifiedLabel]
    /// Confiance maximale parmi les libellés jugés vocaux.
    public let vocalConfidence: Double
    /// Renseigné quand la mesure a échoué, partiellement ou totalement.
    public let failure: String?

    public struct ClassifiedLabel: Hashable, Sendable {
        public let identifier: String
        public let confidence: Double
        public init(identifier: String, confidence: Double) {
            self.identifier = identifier
            self.confidence = confidence
        }
    }

    public init(fileName: String, duration: TimeInterval, peakDB: Float, isSilent: Bool,
                labels: [ClassifiedLabel], vocalConfidence: Double, failure: String?) {
        self.fileName = fileName
        self.duration = duration
        self.peakDB = peakDB
        self.isSilent = isSilent
        self.labels = labels
        self.vocalConfidence = vocalConfidence
        self.failure = failure
    }

    public var containsVocal: Bool {
        vocalConfidence >= AudioAnalysisPolicy.vocalConfidenceThreshold
    }

    public var summary: String {
        if let failure { return "erreur : \(failure)" }
        if isSilent { return "silencieux" }
        if vocalConfidence > 0 { return String(format: "voix %.0f %%", vocalConfidence * 100) }
        return "pas de voix détectée"
    }
}

/// Mesures agrégées pour un projet.
public struct AudioAnalysisReport: Hashable, Sendable {
    public let files: [AudioFileMeasurement]
    public init(files: [AudioFileMeasurement]) { self.files = files }

    public static let empty = AudioAnalysisReport(files: [])

    public var containsVocal: Bool { files.contains(where: \.containsVocal) }
    /// Au moins un fichier mesuré avec succès et non silencieux.
    public var containsSignal: Bool { files.contains { !$0.isSilent && $0.failure == nil } }
    public var maxVocalConfidence: Double { files.map(\.vocalConfidence).max() ?? 0 }

    public var note: String {
        if files.isEmpty { return "aucun fichier audio" }
        if containsVocal { return String(format: "voix détectée (%.0f %%)", maxVocalConfidence * 100) }
        if !containsSignal { return "tous les fichiers sont silencieux" }
        return "signal présent, pas de voix détectée"
    }
}

/// Seuils et vocabulaire de l'étage 3, isolés pour être testables et ajustables
/// sans toucher au code de décodage.
public enum AudioAnalysisPolicy {

    /// Crête en dessous de laquelle un fichier ne contient rien d'exploitable.
    public static let silenceThresholdDB: Float = -60

    /// Confiance minimale pour retenir « voix présente ».
    public static let vocalConfidenceThreshold = 0.5

    /// Confiance en dessous de laquelle un libellé est ignoré, pour ne pas
    /// conserver la longue traîne du classifieur.
    public static let labelNoiseFloor = 0.05

    /// Durée décodée au maximum par fichier. Au-delà on paie sans rien gagner :
    /// une voix présente dans un enregistrement l'est dès les premières dizaines
    /// de secondes.
    public static let maximumAnalyzedDuration: TimeInterval = 90

    /// Nombre de fichiers inspectés au maximum par projet.
    public static let maximumFilesPerProject = 12

    /// Nombre de libellés conservés par fichier, pour affichage.
    public static let reportedLabelCount = 6

    /// Extensions reconnues comme audio.
    public static let audioExtensions: Set<String> = ["wav", "aif", "aiff", "caf", "mp3", "m4a"]

    /// Jetons identifiant un libellé vocal dans la taxonomie du classifieur.
    ///
    /// La taxonomie exacte d'Apple n'étant pas documentée de façon stable,
    /// l'app affiche les libellés bruts : si un libellé vocal apparaît sans
    /// être reconnu, il suffit de l'ajouter ici.
    public static let vocalTokens = ["speech", "sing", "vocal", "voice", "humming",
                                     "rapping", "choir", "chant", "yodel", "whisper"]

    public static func isVocalLabel(_ identifier: String) -> Bool {
        let lowered = identifier.lowercased()
        return vocalTokens.contains { lowered.contains($0) }
    }

    public static func vocalConfidence(from scores: [String: Double]) -> Double {
        scores.lazy.filter { isVocalLabel($0.key) }.map(\.value).max() ?? 0
    }

    public static func isSilent(peakDB: Float) -> Bool { peakDB < silenceThresholdDB }

    public static func isAudioFile(_ url: URL) -> Bool {
        audioExtensions.contains(url.pathExtension.lowercased())
    }
}

/// Abstraction de l'étage 3.
///
/// Permet de piloter l'interface et les tests avec une implémentation factice :
/// les tests de l'enchaînement des verdicts n'ont pas à fabriquer de vrais
/// fichiers audio ni à dépendre de la disponibilité du classifieur système.
public protocol AudioAnalyzing: Sendable {
    func audioFiles(in project: URL) -> [URL]
    func analyze(project: URL) async -> AudioAnalysisReport
}
