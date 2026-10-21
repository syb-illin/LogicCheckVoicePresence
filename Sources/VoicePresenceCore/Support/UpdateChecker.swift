import Foundation

/// Une version publiée sur GitHub Releases.
public struct Release: Sendable, Hashable {
    public let version: SemanticVersion
    public let tag: String
    public let title: String
    public let notes: String
    public let pageURL: URL
    /// Archive téléchargeable, si la release en fournit une.
    public let downloadURL: URL?
    public let publishedAt: Date?

    public init(version: SemanticVersion, tag: String, title: String, notes: String,
                pageURL: URL, downloadURL: URL?, publishedAt: Date?) {
        self.version = version
        self.tag = tag
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
    }
}

/// Résultat d'une vérification de mise à jour.
public enum UpdateStatus: Sendable, Equatable {
    case upToDate(current: SemanticVersion)
    case updateAvailable(Release)
    /// Échec explicite : réseau coupé, quota dépassé, réponse inattendue.
    /// Distingué de « à jour » pour ne pas faire croire à tort que tout va bien.
    case failed(String)

    public var release: Release? {
        if case let .updateAvailable(release) = self { return release }
        return nil
    }
}

/// Abstraction du transport, pour tester sans réseau.
public protocol ReleaseFetching: Sendable {
    func fetchLatestRelease() async throws -> Data
}

/// Interroge l'API publique GitHub Releases.
///
/// Endpoint non authentifié : limité à 60 requêtes par heure et par IP, ce qui
/// est sans conséquence pour une vérification au lancement.
public struct GitHubReleaseFetcher: ReleaseFetching {
    private let owner: String
    private let repository: String
    private let session: URLSession

    public init(owner: String = AppInfo.repositoryOwner,
                repository: String = AppInfo.repositoryName,
                session: URLSession = .shared) {
        self.owner = owner
        self.repository = repository
        self.session = session
    }

    public func fetchLatestRelease() async throws -> Data {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        // Court : la vérification ne doit jamais retarder le lancement.
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.unexpectedResponse("réponse non HTTP")
        }
        switch http.statusCode {
        case 200:
            return data
        case 404:
            // Aucune release publiée : ce n'est pas une anomalie.
            throw UpdateError.noReleases
        case 403, 429:
            throw UpdateError.rateLimited
        default:
            throw UpdateError.unexpectedResponse("HTTP \(http.statusCode)")
        }
    }
}

public enum UpdateError: LocalizedError, Equatable {
    case noReleases
    case rateLimited
    case unexpectedResponse(String)
    case malformedPayload

    public var errorDescription: String? {
        switch self {
        case .noReleases: "Aucune version publiée."
        case .rateLimited: "Quota de l'API GitHub atteint, réessaie plus tard."
        case .unexpectedResponse(let detail): "Réponse inattendue de GitHub (\(detail))."
        case .malformedPayload: "Réponse GitHub illisible."
        }
    }
}

/// Compare la version installée à la dernière publiée.
///
/// ## Pourquoi pas de mise à jour silencieuse
///
/// Remplacer l'app et la relancer sans intervention suppose de vérifier la
/// signature de ce qu'on installe. Sans Developer ID Apple, l'app n'est que
/// signée ad hoc : une mise à jour automatique installerait un binaire dont
/// l'origine n'est pas vérifiable, et Gatekeeper rebloquerait le résultat à
/// chaque fois. Ce vérificateur se contente donc de **prévenir** et d'ouvrir la
/// page de release ; l'utilisateur garde la main sur ce qu'il installe.
///
/// Avec un Developer ID et une notarisation, Sparkle (appcast adossé aux
/// GitHub Releases, signatures EdDSA) devient le bon outil et remplacerait ce
/// type sans toucher au reste de l'app.
public struct UpdateChecker: Sendable {
    private let fetcher: any ReleaseFetching
    private let currentVersion: SemanticVersion
    /// Proposer ou non les préversions.
    private let includePrereleases: Bool

    public init(fetcher: any ReleaseFetching = GitHubReleaseFetcher(),
                currentVersion: SemanticVersion? = nil,
                includePrereleases: Bool = false) {
        self.fetcher = fetcher
        self.currentVersion = currentVersion
            ?? SemanticVersion(AppInfo.version)
            ?? SemanticVersion(major: 0, minor: 0, patch: 0)
        self.includePrereleases = includePrereleases
    }

    public func check() async -> UpdateStatus {
        do {
            let release = try Self.decodeRelease(from: try await fetcher.fetchLatestRelease())
            if release.version.isPrerelease, !includePrereleases {
                Log.updates.debug("Préversion ignorée : \(release.tag, privacy: .public)")
                return .upToDate(current: currentVersion)
            }
            if release.version > currentVersion {
                Log.updates.info("Mise à jour disponible : \(release.tag, privacy: .public)")
                return .updateAvailable(release)
            }
            Log.updates.debug("À jour (\(currentVersion.description, privacy: .public))")
            return .upToDate(current: currentVersion)
        } catch UpdateError.noReleases {
            return .upToDate(current: currentVersion)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Log.updates.notice("Vérification impossible : \(message, privacy: .public)")
            return .failed(message)
        }
    }

    // MARK: - Décodage

    /// Forme minimale de la réponse GitHub, limitée aux champs utilisés.
    private struct Payload: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL
        let publishedAt: Date?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            // Clés explicites : la stratégie de décodage par défaut ne convertit
            // pas `browser_download_url`, et l'omettre faisait échouer tout le
            // décodage de la release.
            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name, body
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case assets
        }
    }

    static func decodeRelease(from data: Data) throws -> Release {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw UpdateError.malformedPayload
        }
        guard let version = SemanticVersion(payload.tagName) else {
            throw UpdateError.malformedPayload
        }
        // On privilégie une archive, à défaut le premier asset proposé.
        let asset = payload.assets.first { $0.name.lowercased().hasSuffix(".zip") }
            ?? payload.assets.first
        return Release(version: version,
                       tag: payload.tagName,
                       title: payload.name ?? payload.tagName,
                       notes: payload.body ?? "",
                       pageURL: payload.htmlURL,
                       downloadURL: asset?.browserDownloadURL,
                       publishedAt: payload.publishedAt)
    }
}
