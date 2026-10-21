import Foundation

/// Événements émis pendant un scan.
public enum ScanEvent: Sendable {
    /// Découverte terminée : nombre de projets à traiter.
    case discovered(total: Int)
    /// Un projet vient d'être inspecté.
    case inspected(ProjectInspection, completed: Int, total: Int)
    /// Scan terminé, avec sa durée.
    case finished(duration: TimeInterval, completed: Int)
}

/// Orchestration du scan, en parallèle et borné.
///
/// ## Pourquoi un parallélisme borné
///
/// Chaque projet est indépendant : le travail se répartit naturellement sur les
/// cœurs. Mais une tâche par projet lancée d'un coup ferait mapper des centaines
/// de fichiers simultanément, pour un pic mémoire proportionnel à la taille du
/// corpus. Le groupe est donc maintenu à `concurrencyLimit` tâches vives : une
/// nouvelle n'est ajoutée qu'au retour d'une précédente.
///
/// Le travail étant dominé par la lecture disque et le décodage, la limite est
/// calée sur le nombre de cœurs actifs, avec un plancher qui garde l'app
/// réactive sur une machine à un seul cœur.
///
/// ## Annulation
///
/// La coopération est vérifiée à chaque itération : fermer la fenêtre ou relancer
/// un scan interrompt les tâches en vol sans attendre la fin du corpus.
public struct ScanCoordinator: Sendable {
    private let locator: ProjectLocator
    private let inspector: ProjectInspector
    private let concurrencyLimit: Int

    public init(locator: ProjectLocator = ProjectLocator(),
                inspector: ProjectInspector = ProjectInspector(),
                concurrencyLimit: Int? = nil) {
        self.locator = locator
        self.inspector = inspector
        self.concurrencyLimit = concurrencyLimit ?? Self.defaultConcurrencyLimit
    }

    public static var defaultConcurrencyLimit: Int {
        max(2, min(ProcessInfo.processInfo.activeProcessorCount, 12))
    }

    /// Scanne `root` et émet les résultats au fil de l'eau.
    ///
    /// Le flux est à tampon illimité : l'interface peut consommer moins vite que
    /// la production sans bloquer les tâches de calcul, et aucun événement n'est
    /// perdu si l'affichage est occupé.
    public func scan(root: URL, busName: String) -> AsyncStream<ScanEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            let task = Task.detached(priority: .userInitiated) { [locator, inspector, concurrencyLimit] in
                let started = Date()
                let signpost = Log.signposter.beginInterval("scan", id: Log.signposter.makeSignpostID())
                defer { Log.signposter.endInterval("scan", signpost) }

                let projects = locator.projects(under: root)
                continuation.yield(.discovered(total: projects.count))

                guard !projects.isEmpty else {
                    continuation.yield(.finished(duration: 0, completed: 0))
                    continuation.finish()
                    return
                }

                Log.scan.info("Scan de \(projects.count, privacy: .public) projet(s), \(concurrencyLimit, privacy: .public) en parallèle")

                var completed = 0
                await withTaskGroup(of: ProjectInspection.self) { group in
                    var next = 0
                    // Amorçage : on remplit le groupe jusqu'à la limite.
                    while next < min(concurrencyLimit, projects.count) {
                        let url = projects[next]
                        group.addTask { inspector.inspect(project: url, busName: busName) }
                        next += 1
                    }

                    // Régime permanent : une tâche ajoutée par tâche terminée.
                    while let inspection = await group.next() {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }
                        completed += 1
                        continuation.yield(.inspected(inspection,
                                                      completed: completed,
                                                      total: projects.count))
                        if next < projects.count {
                            let url = projects[next]
                            group.addTask { inspector.inspect(project: url, busName: busName) }
                            next += 1
                        }
                    }
                }

                let duration = Date().timeIntervalSince(started)
                Log.scan.info("Scan terminé : \(completed, privacy: .public) projet(s) en \(String(format: "%.2f", duration), privacy: .public) s")
                continuation.yield(.finished(duration: duration, completed: completed))
                continuation.finish()
            }

            // Consommateur disparu (fenêtre fermée, scan relancé) : les tâches
            // s'arrêtent au lieu de continuer à brûler du CPU en arrière-plan.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
