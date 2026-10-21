import Foundation

/// Identité et version de l'app, lues depuis le bundle avec repli sur des
/// constantes de compilation.
///
/// Les valeurs viennent de `Info.plist`, généré au build à partir du tag git.
/// Le repli est nécessaire parce que les tests tournent sans bundle applicatif :
/// `Bundle.main` y désigne le harnais de test, pas l'app.
public enum AppInfo {

    /// Nom affiché dans l'interface et la fenêtre « À propos ».
    public static let name = "Logic Check Voice Presence"

    /// Nom du bundle et des artefacts de release.
    public static let bundleName = "LogicCheckVoicePresence"

    public static let bundleIdentifier = "io.github.sybillin.LogicCheckVoicePresence"

    /// Auteur affiché dans « À propos ».
    public static let author = "Ren"
    public static let authorHandle = "syb-illin"

    public static let repositoryOwner = "syb-illin"
    public static let repositoryName = "LogicCheckVoicePresence"

    public static var repositoryURL: URL {
        URL(string: "https://github.com/\(repositoryOwner)/\(repositoryName)")!
    }

    public static var releasesURL: URL { repositoryURL.appendingPathComponent("releases") }
    public static var issuesURL: URL { repositoryURL.appendingPathComponent("issues") }
    public static var authorURL: URL { URL(string: "https://github.com/\(authorHandle)")! }

    /// Version marketing, par exemple `1.2.0`.
    public static var version: String {
        bundleString("CFBundleShortVersionString") ?? fallbackVersion
    }

    /// Numéro de build, généralement le nombre de commits.
    public static var build: String { bundleString("CFBundleVersion") ?? "0" }

    public static var versionDisplay: String { "v\(version) (build \(build))" }

    /// Version utilisée hors bundle applicatif, notamment sous test.
    static let fallbackVersion = "0.0.0"

    private static func bundleString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else { return nil }
        return value
    }

    public static var copyright: String {
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        return "© \(year) \(author)"
    }
}
