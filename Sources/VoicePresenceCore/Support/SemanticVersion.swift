import Foundation

/// Version sémantique comparable.
///
/// Comparer des versions comme des chaînes est faux : `"1.10.0" < "1.9.0"` en
/// ordre lexicographique. Ce type compare composant par composant, et traite le
/// cas des préversions selon semver — une préversion précède toujours la version
/// finale correspondante (`1.0.0-beta.1 < 1.0.0`).
public struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int
    /// Identifiants de préversion, sans le tiret. Vide pour une version finale.
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// Analyse une chaîne de version, avec ou sans préfixe `v`.
    ///
    /// Accepte les formes courtes (`"1"`, `"1.2"`) en complétant par des zéros,
    /// parce que les tags de release n'ont pas toujours trois composants.
    /// Renvoie `nil` si rien d'exploitable n'en ressort, plutôt que de deviner.
    public init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        // Les métadonnées de build (`+sha`) n'entrent pas dans la comparaison.
        let withoutBuild = text.split(separator: "+", maxSplits: 1).first.map(String.init) ?? text
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !core.isEmpty, core.count <= 3 else { return nil }

        var numbers: [Int] = []
        for component in core {
            guard let value = Int(component), value >= 0 else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }

        self.major = numbers[0]
        self.minor = numbers[1]
        self.patch = numbers[2]
        if parts.count == 2, !parts[1].isEmpty {
            self.prerelease = parts[1].split(separator: ".").map(String.init)
        } else {
            self.prerelease = []
        }
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : "\(core)-\(prerelease.joined(separator: "."))"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        // Semver : une version avec préversion précède la version finale.
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false   // finale > préversion
        case (false, true): return true    // préversion < finale
        case (false, false): break
        }

        // Comparaison composant par composant : numérique si les deux le sont,
        // lexicographique sinon, comme le prescrit semver.
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) {
            if left == right { continue }
            switch (Int(left), Int(right)) {
            case let (l?, r?): return l < r
            case (_?, nil): return true     // numérique < alphanumérique
            case (nil, _?): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
