import Foundation
import Observation
import VoicePresenceCore

/// État de l'interface et pilotage des trois étages d'analyse.
///
/// `@Observable` (Observation, macOS 14) plutôt que `ObservableObject` : le suivi
/// est par propriété, donc une vue qui n'affiche que la progression n'est pas
/// réévaluée quand la liste des résultats change.
///
/// Cantonné au `MainActor` : l'état n'est muté que depuis le fil principal, le
/// calcul se faisant dans ``ScanCoordinator``. Aucun verrou, aucune course.
@MainActor
@Observable
public final class ScanViewModel {

    // MARK: - État observable

    public private(set) var inspections: [ProjectInspection] = []
    public private(set) var phase: Phase = .idle
    public private(set) var progress = Progress()
    public private(set) var lastScanDuration: TimeInterval?
    public private(set) var updateStatus: UpdateStatus?

    public var busName = "voice bus"
    public var nameFilter = ""
    public var verdictFilter: Verdict?
    public private(set) var folder: URL?

    public enum Phase: Equatable {
        case idle
        case scanning
        case analyzingAudio
        case done(String)

        public var isBusy: Bool { self == .scanning || self == .analyzingAudio }
    }

    public struct Progress: Equatable {
        public var completed = 0
        public var total = 0
        public var label = ""
        public var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    // MARK: - Dépendances

    private let coordinator: ScanCoordinator
    private let audioAnalyzer: any AudioAnalyzing
    private let updateChecker: UpdateChecker

    /// Une seule tâche en vol : en lancer une nouvelle annule la précédente, ce
    /// qui évite deux scans concurrents écrivant dans le même état.
    private var runningTask: Task<Void, Never>?

    public init(coordinator: ScanCoordinator = ScanCoordinator(),
                audioAnalyzer: any AudioAnalyzing = SystemAudioAnalyzer(),
                updateChecker: UpdateChecker = UpdateChecker()) {
        self.coordinator = coordinator
        self.audioAnalyzer = audioAnalyzer
        self.updateChecker = updateChecker
    }

    // MARK: - Dérivés

    public var filteredInspections: [ProjectInspection] {
        inspections.lazy
            .filter { verdictFilter == nil || $0.verdict == verdictFilter }
            .filter { nameFilter.isEmpty || $0.name.localizedCaseInsensitiveContains(nameFilter) }
            .sorted {
                ($0.verdict.sortRank, $0.name.localizedLowercase)
                    < ($1.verdict.sortRank, $1.name.localizedLowercase)
            }
    }

    public var verdictCounts: [(verdict: Verdict, count: Int)] {
        ReportExporter.summary(inspections).map { (verdict: $0.0, count: $0.1) }
    }

    public var pendingAudioAnalysisCount: Int {
        inspections.filter(\.needsAudioAnalysis).count
    }

    public var canExport: Bool { !inspections.isEmpty && !phase.isBusy }

    // MARK: - Étages 1 et 2

    public func scan(folder url: URL) {
        runningTask?.cancel()
        folder = url
        inspections = []
        verdictFilter = nil
        phase = .scanning
        progress = Progress(completed: 0, total: 0, label: "Recherche des projets…")

        let name = busName
        runningTask = Task { [coordinator] in
            // Tampon local : publier dans `inspections` à chaque projet ferait
            // recalculer la table des centaines de fois pour rien.
            var buffer: [ProjectInspection] = []
            for await event in coordinator.scan(root: url, busName: name) {
                if Task.isCancelled { break }
                switch event {
                case .discovered(let total):
                    buffer.reserveCapacity(total)
                    progress = Progress(completed: 0, total: total,
                                        label: total == 0 ? "Aucun projet .logicx trouvé"
                                                          : "\(total) projet(s) à analyser")
                case .inspected(let inspection, let completed, let total):
                    buffer.append(inspection)
                    progress = Progress(completed: completed, total: total,
                                        label: "\(completed) / \(total) — \(inspection.name)")
                    if completed % Self.publishStride == 0 { inspections = buffer }
                case .finished(let duration, let completed):
                    inspections = buffer
                    lastScanDuration = duration
                    phase = .done(Self.completionLabel(completed: completed, duration: duration))
                }
            }
            if Task.isCancelled {
                inspections = buffer
                phase = .done("Scan interrompu — \(buffer.count) projet(s) analysé(s)")
            }
        }
    }

    public func rescan() {
        guard let folder else { return }
        scan(folder: folder)
    }

    public func cancel() {
        runningTask?.cancel()
        runningTask = nil
        phase = .done("Interrompu")
    }

    // MARK: - Étage 3

    /// Lance l'analyse audio sur les seuls projets indécidables.
    public func analyzePendingAudio() {
        let targets = inspections.indices.filter { inspections[$0].needsAudioAnalysis }
        guard !targets.isEmpty else { return }
        runAudioAnalysis(on: targets, label: "Analyse audio")
    }

    /// Analyse un projet précis, même si son verdict ne l'exigeait pas.
    public func analyzeAudio(for inspection: ProjectInspection) {
        guard let index = inspections.firstIndex(where: { $0.id == inspection.id }) else { return }
        runAudioAnalysis(on: [index], label: "Analyse audio — \(inspection.name)")
    }

    private func runAudioAnalysis(on indices: [Int], label: String) {
        runningTask?.cancel()
        phase = .analyzingAudio
        progress = Progress(completed: 0, total: indices.count, label: label)

        runningTask = Task { [audioAnalyzer] in
            var done = 0
            for index in indices {
                if Task.isCancelled { break }
                // L'index peut avoir été invalidé par un rescan concurrent.
                guard inspections.indices.contains(index) else { continue }
                let target = inspections[index]
                let report = await audioAnalyzer.analyze(project: target.url)
                guard inspections.indices.contains(index),
                      inspections[index].id == target.id else { continue }
                inspections[index].audioAnalysis = report
                done += 1
                progress = Progress(completed: done, total: indices.count,
                                    label: "\(label) \(done) / \(indices.count) — \(target.name)")
            }
            phase = .done(Task.isCancelled ? "Analyse audio interrompue"
                                           : "Analyse audio terminée — \(done) projet(s)")
        }
    }

    // MARK: - Mise à jour

    /// Vérifie la disponibilité d'une mise à jour.
    ///
    /// `async` plutôt qu'un `Task` interne : l'appelant sait quand c'est terminé
    /// et peut afficher un indicateur sans scruter l'état en boucle.
    public func checkForUpdates() async {
        updateStatus = await updateChecker.check()
    }

    // MARK: - Export

    public func csv() -> String { ReportExporter.csv(inspections) }

    public func defaultExportFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let slug = busName.replacingOccurrences(of: " ", with: "-")
        return "\(slug)-\(formatter.string(from: Date())).csv"
    }

    // MARK: - Détails

    /// Fréquence de publication pendant le scan : assez rare pour ne pas saturer
    /// le rendu, assez fréquente pour que la liste se remplisse visiblement.
    private static let publishStride = 25

    private static func completionLabel(completed: Int, duration: TimeInterval) -> String {
        completed == 0
            ? "Aucun projet analysé"
            : String(format: "%d projet(s) analysé(s) en %.1f s", completed, duration)
    }
}
