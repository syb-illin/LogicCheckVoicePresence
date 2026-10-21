import Foundation
import AVFoundation
import SoundAnalysis

/// Étage 3 : mesure du contenu audio, avec les frameworks système uniquement.
///
/// - `AVFoundation` décode et donne la crête : déterministe, sans modèle.
/// - `SoundAnalysis` classe le contenu avec le classifieur embarqué de macOS,
///   on-device, sans réseau ni téléchargement.
///
/// Aucune dépendance tierce : pas de `torch`, pas de modèle à récupérer, rien à
/// installer. En contrepartie la taxonomie du classifieur n'est pas un contrat
/// stable, donc les libellés bruts sont remontés jusqu'à l'interface.
///
/// Ne tourne jamais pendant le scan : déclenché explicitement, sur les projets
/// ``Verdict/undecidable`` seulement.
public struct SystemAudioAnalyzer: AudioAnalyzing {

    public init() {}

    public func audioFiles(in project: URL) -> [URL] {
        let media = project.appendingPathComponent("Media/Audio Files", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: media, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries
            .filter(AudioAnalysisPolicy.isAudioFile)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public func analyze(project: URL) async -> AudioAnalysisReport {
        let files = audioFiles(in: project).prefix(AudioAnalysisPolicy.maximumFilesPerProject)
        guard !files.isEmpty else { return .empty }

        Log.audio.info("Analyse audio de \(files.count, privacy: .public) fichier(s)")
        let state = Log.signposter.beginInterval("audio-analysis", id: Log.signposter.makeSignpostID())
        defer { Log.signposter.endInterval("audio-analysis", state) }

        var measurements: [AudioFileMeasurement] = []
        measurements.reserveCapacity(files.count)
        for file in files {
            if Task.isCancelled { break }
            measurements.append(measure(file: file))
        }
        return AudioAnalysisReport(files: measurements)
    }

    // MARK: - Mesure d'un fichier

    func measure(file url: URL) -> AudioFileMeasurement {
        let name = url.lastPathComponent

        let level: (peakDB: Float, duration: TimeInterval)
        do {
            level = try Self.peakLevel(of: url)
        } catch {
            Log.audio.error("Décodage impossible : \(error.localizedDescription, privacy: .public)")
            return AudioFileMeasurement(fileName: name, duration: 0, peakDB: -.infinity,
                                        isSilent: false, labels: [], vocalConfidence: 0,
                                        failure: error.localizedDescription)
        }

        // Le silence se tranche sans modèle : inutile de payer la classification.
        if AudioAnalysisPolicy.isSilent(peakDB: level.peakDB) {
            return AudioFileMeasurement(fileName: name, duration: level.duration,
                                        peakDB: level.peakDB, isSilent: true,
                                        labels: [], vocalConfidence: 0, failure: nil)
        }

        do {
            let scores = try Self.classify(url)
            let labels = scores
                .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
                .prefix(AudioAnalysisPolicy.reportedLabelCount)
                .map { AudioFileMeasurement.ClassifiedLabel(identifier: $0.key, confidence: $0.value) }
            return AudioFileMeasurement(fileName: name, duration: level.duration,
                                        peakDB: level.peakDB, isSilent: false,
                                        labels: labels,
                                        vocalConfidence: AudioAnalysisPolicy.vocalConfidence(from: scores),
                                        failure: nil)
        } catch {
            // Classifieur indisponible : la crête et la durée restent valides et
            // suffisent à distinguer un fichier vide d'un fichier rempli.
            Log.audio.notice("Classifieur indisponible : \(error.localizedDescription, privacy: .public)")
            return AudioFileMeasurement(fileName: name, duration: level.duration,
                                        peakDB: level.peakDB, isSilent: false,
                                        labels: [], vocalConfidence: 0,
                                        failure: "classifieur indisponible")
        }
    }

    /// Crête et durée, par lecture en blocs.
    ///
    /// Le tampon est alloué une fois et réutilisé : pas d'allocation par bloc,
    /// donc pas de pression mémoire qui monterait avec la durée du fichier.
    static func peakLevel(of url: URL) throws -> (peakDB: Float, duration: TimeInterval) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, format.channelCount > 0 else { return (-.infinity, 0) }

        let duration = TimeInterval(file.length) / sampleRate
        let framesToRead = AVAudioFramePosition(
            min(Double(file.length), AudioAnalysisPolicy.maximumAnalyzedDuration * sampleRate))

        let blockSize: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: blockSize) else {
            return (-.infinity, duration)
        }

        var peak: Float = 0
        var framesRead: AVAudioFramePosition = 0

        while framesRead < framesToRead {
            try file.read(into: buffer, frameCount: blockSize)
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { break }
            guard let channelData = buffer.floatChannelData else { break }

            for channel in 0..<Int(format.channelCount) {
                let samples = UnsafeBufferPointer(start: channelData[channel], count: frames)
                for sample in samples {
                    let magnitude = abs(sample)
                    if magnitude > peak { peak = magnitude }
                }
            }
            framesRead += AVAudioFramePosition(frames)
        }

        return (peak > 0 ? 20 * log10(peak) : -.infinity, duration)
    }

    /// Classification par le modèle embarqué. Synchrone : `analyze()` rend la
    /// main quand le fichier est entièrement traité.
    static func classify(_ url: URL) throws -> [String: Double] {
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        let collector = ScoreCollector()
        try analyzer.add(request, withObserver: collector)
        analyzer.analyze()
        if let failure = collector.failure { throw failure }
        return collector.bestScores
    }

    /// Agrège la confiance maximale par libellé sur toutes les fenêtres.
    ///
    /// `SNAudioFileAnalyzer` ne retient pas son observateur : il est donc gardé
    /// en vie par la pile de `classify(_:)` le temps de l'appel synchrone, et
    /// libéré à la sortie. Aucune référence croisée, donc aucun cycle.
    private final class ScoreCollector: NSObject, SNResultsObserving {
        private(set) var bestScores: [String: Double] = [:]
        private(set) var failure: Error?

        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let classification = result as? SNClassificationResult else { return }
            for candidate in classification.classifications
            where candidate.confidence > AudioAnalysisPolicy.labelNoiseFloor {
                let previous = bestScores[candidate.identifier] ?? 0
                bestScores[candidate.identifier] = max(previous, candidate.confidence)
            }
        }

        func request(_ request: SNRequest, didFailWithError error: Error) {
            failure = error
        }
    }
}
