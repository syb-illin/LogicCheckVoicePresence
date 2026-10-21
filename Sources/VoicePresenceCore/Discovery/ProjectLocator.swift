import Foundation

/// Localisation des projets Logic sur le disque.
///
/// Un `.logicx` est un *bundle* : un dossier que le Finder présente comme un
/// fichier. Son contenu utile ici :
///
/// ```
/// Projet.logicx/
///   Alternatives/
///     000/ProjectData          <- une alternative
///     001/ProjectData
///       Project File Backups/  <- sauvegardes, à ignorer
///   Media/Audio Files/         <- fichiers audio du projet
///   ProjectData                <- emplacement des versions anciennes
/// ```
public struct ProjectLocator: Sendable {

    public init() {}

    /// Chemins des bundles `.logicx` sous `root`, triés par nom.
    ///
    /// `skipsPackageDescendants` empêche de descendre dans les bundles, qui
    /// peuvent contenir des milliers de fichiers : sur un dossier de plusieurs
    /// centaines de projets, descendre dedans coûterait des minutes.
    /// Si `root` est lui-même un bundle, il est renvoyé seul.
    public func projects(under root: URL) -> [URL] {
        if root.pathExtension == Self.bundleExtension { return [root] }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            Log.discovery.error("Dossier illisible")
            return []
        }

        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == Self.bundleExtension {
            found.append(url)
            // Un bundle non enregistré auprès du système n'est pas considéré
            // comme un paquet par l'énumérateur : on coupe la descente
            // explicitement pour ne pas parcourir son contenu.
            enumerator.skipDescendants()
        }

        Log.discovery.info("\(found.count, privacy: .public) projet(s) trouvé(s)")
        return found.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    /// Alternative la plus récemment modifiée d'un projet.
    ///
    /// Les `Project File Backups` sont écartés par construction : seuls les
    /// `Alternatives/<n>/ProjectData` sont examinés, jamais leurs sous-dossiers.
    public func latestProjectData(in project: URL) -> ProjectDataLocation? {
        let fileManager = FileManager.default
        let alternativesRoot = project.appendingPathComponent("Alternatives", isDirectory: true)

        var newest: ProjectDataLocation?
        if let alternatives = try? fileManager.contentsOfDirectory(
            at: alternativesRoot, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) {
            for alternative in alternatives {
                let candidate = alternative.appendingPathComponent("ProjectData")
                guard let date = Self.modificationDate(of: candidate) else { continue }
                if newest == nil || date > newest!.modifiedAt {
                    newest = ProjectDataLocation(url: candidate,
                                                 alternative: alternative.lastPathComponent,
                                                 modifiedAt: date)
                }
            }
        }
        if let newest { return newest }

        // Versions anciennes : ProjectData à la racine du bundle.
        let legacy = project.appendingPathComponent("ProjectData")
        guard let date = Self.modificationDate(of: legacy) else { return nil }
        return ProjectDataLocation(url: legacy, alternative: "—", modifiedAt: date)
    }

    private static func modificationDate(of url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey,
                                                             .isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        // Un fichier sans date reste utilisable : il est simplement le plus ancien.
        return values.contentModificationDate ?? .distantPast
    }

    public static let bundleExtension = "logicx"
}

/// Un `ProjectData` localisé, avec l'alternative dont il provient.
public struct ProjectDataLocation: Hashable, Sendable {
    public let url: URL
    public let alternative: String
    public let modifiedAt: Date

    public init(url: URL, alternative: String, modifiedAt: Date) {
        self.url = url
        self.alternative = alternative
        self.modifiedAt = modifiedAt
    }
}
