import Foundation

/// Rattachement des régions audio aux canaux du mixeur.
///
/// ## Pourquoi ce n'est pas structurel
///
/// Les régions ne référencent pas leur canal par un champ exploitable. Vérifié
/// par deux tests indépendants sur des projets réels :
///
/// 1. Aucun offset du chunk `gRuA` ne contient le slot du canal attendu, pour
///    aucune région dont le canal était connu par ailleurs.
/// 2. Aucun offset n'est constant au sein d'un groupe de régions partageant un
///    canal tout en étant distinct entre groupes — ce qu'un index de piste
///    serait nécessairement.
///
/// Les chunks `karT` (pistes) sont à longueur variable, donc sans offset fixe
/// exploitable, et `ProjectData` ne contient aucun chemin de fichier audio
/// (`.wav` n'y apparaît jamais). Le rattachement passe donc par le nom.
///
/// ## La subtilité des noms
///
/// Logic fige le nom d'une région au moment de l'enregistrement. Renommer la
/// piste ensuite désynchronise les deux : une piste `Voice chorus b R` peut
/// porter des régions encore nommées `Voice chorus`. La comparaison doit donc
/// marcher **dans les deux sens**, le nom du canal pouvant prolonger celui de
/// la région comme l'inverse.
///
/// ## Ce qui évite les faux positifs
///
/// Chaque région est mise en concurrence sur **tous** les canaux du projet, pas
/// seulement ceux liés au bus cherché. Une région `kick` perd donc face au
/// canal `kick` même si un canal `k…` est lié au bus. Et quand plusieurs canaux
/// sont à égalité, la région n'est attribuée à aucun : elle est comptée une
/// seule fois comme ambiguë, au niveau du projet.
public struct RegionAttribution: Sendable {

    /// Régions attribuées de façon certaine, par slot de canal.
    public let firmCounts: [Int: Int]
    /// Régions dont le meilleur candidat est à égalité entre plusieurs canaux,
    /// dont au moins un lié au bus. Comptées une fois chacune.
    public let ambiguousCount: Int

    public init(firmCounts: [Int: Int], ambiguousCount: Int) {
        self.firmCounts = firmCounts
        self.ambiguousCount = ambiguousCount
    }

    public static let none = RegionAttribution(firmCounts: [:], ambiguousCount: 0)

    public func firmCount(for slot: Int) -> Int { firmCounts[slot] ?? 0 }
    public var totalFirm: Int { firmCounts.values.reduce(0, +) }

    // MARK: - Normalisation des noms

    /// Retire les suffixes que Logic ajoute aux régions : `#NN` (numéro de prise)
    /// et `.N` (copie), éventuellement chaînés.
    ///
    /// `"voice verse 1#05.1"` → `"voice verse 1"`
    ///
    /// Un suffixe non numérique n'est pas un suffixe de Logic et reste intact :
    /// `"mix.final"` ne devient pas `"mix"`.
    public static func stem(of regionName: String) -> String {
        var name = Substring(regionName.trimmingCharacters(in: .whitespaces))

        func dropNumericSuffix(after separator: Character) -> Bool {
            guard let index = name.lastIndex(of: separator) else { return false }
            let suffix = name[name.index(after: index)...]
            guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return false }
            name = name[name.startIndex..<index]
            return true
        }

        // Les copies peuvent être chaînées : "take.1.2".
        while dropNumericSuffix(after: ".") {}
        _ = dropNumericSuffix(after: "#")

        return name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Longueur du préfixe commun, en caractères.
    static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var length = 0
        var i = a.startIndex
        var j = b.startIndex
        while i < a.endIndex, j < b.endIndex, a[i] == b[j] {
            length += 1
            i = a.index(after: i)
            j = b.index(after: j)
        }
        return length
    }

    /// Score de correspondance entre le radical d'une région et un nom de canal.
    ///
    /// Une égalité exacte doit toujours gagner contre une correspondance
    /// partielle, d'où le palier : aucun préfixe commun ne peut atteindre le
    /// score d'une égalité.
    static func score(stem: String, channelName: String) -> Int {
        guard !stem.isEmpty, !channelName.isEmpty else { return 0 }
        if stem == channelName { return exactMatchScore + channelName.count }
        guard channelName.hasPrefix(stem) || stem.hasPrefix(channelName) else { return 0 }
        return commonPrefixLength(stem, channelName)
    }

    static let exactMatchScore = 1_000

    // MARK: - Attribution

    /// Attribue les régions aux canaux liés.
    ///
    /// - Parameters:
    ///   - regionNames: noms bruts, doublons inclus.
    ///   - channels: **tous** les canaux du projet — la concurrence est ce qui
    ///     évite d'attribuer à tort une région au bus cherché.
    ///   - linkedSlots: canaux alimentant le bus, seuls à être comptés.
    public static func attribute(regionNames: [String],
                                 channels: [Int: MixerChannel],
                                 linkedSlots: Set<Int>) -> RegionAttribution {
        guard !linkedSlots.isEmpty, !regionNames.isEmpty else { return .none }

        // Noms normalisés une fois pour toutes : la boucle interne tourne
        // régions × canaux, inutile de renormaliser à chaque itération.
        let candidates: [(slot: Int, name: String)] = channels.values
            .map { (slot: $0.slot, name: $0.comparableName) }
            .filter { !$0.name.isEmpty }
        guard !candidates.isEmpty else { return .none }

        var firmCounts: [Int: Int] = [:]
        var ambiguousCount = 0
        // Les projets contiennent souvent des dizaines de régions homonymes :
        // on ne recalcule pas le gagnant pour un radical déjà résolu.
        var resolved: [String: [Int]] = [:]

        for regionName in regionNames {
            let stem = Self.stem(of: regionName)
            guard !stem.isEmpty else { continue }

            let winners: [Int]
            if let cached = resolved[stem] {
                winners = cached
            } else {
                var bestScore = 0
                var best: [Int] = []
                for candidate in candidates {
                    let value = score(stem: stem, channelName: candidate.name)
                    guard value > 0 else { continue }
                    if value > bestScore {
                        bestScore = value
                        best = [candidate.slot]
                    } else if value == bestScore {
                        best.append(candidate.slot)
                    }
                }
                winners = best
                resolved[stem] = best
            }

            guard !winners.isEmpty else { continue }

            if winners.count == 1 {
                if linkedSlots.contains(winners[0]) {
                    firmCounts[winners[0], default: 0] += 1
                }
            } else if winners.contains(where: linkedSlots.contains) {
                ambiguousCount += 1
            }
        }

        return RegionAttribution(firmCounts: firmCounts, ambiguousCount: ambiguousCount)
    }
}
