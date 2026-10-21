import Foundation

/// Lecteur d'octets à bornes vérifiées, par-dessus `Data`.
///
/// Conçu pour du binaire non fiable : le ProjectData est un format propriétaire
/// non documenté, lu sur des fichiers que l'app n'a pas écrits. Toute lecture
/// hors bornes renvoie `nil` au lieu de faire planter l'app — aucun
/// `data[offset]` nu, aucun `!`, aucune arithmétique de pointeur non vérifiée.
///
/// Travaille directement sur le `Data` (qui peut être mappé en mémoire) sans le
/// copier dans un tableau : sur un corpus de plusieurs centaines de projets de
/// quelques Mo chacun, la copie dominerait le coût total.
public struct ByteReader: Sendable {
    public let data: Data
    /// Index de base : `Data` issu d'une tranche ne commence pas forcément à 0.
    private let base: Data.Index

    public init(_ data: Data) {
        self.data = data
        self.base = data.startIndex
    }

    public var count: Int { data.count }

    /// Octet à `offset`, ou `nil` hors bornes.
    public func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return data[base + offset]
    }

    /// Entier 16 bits non signé, petit-boutiste.
    public func u16(at offset: Int) -> Int? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        let lo = Int(data[base + offset])
        let hi = Int(data[base + offset + 1])
        return lo | (hi << 8)
    }

    /// Vrai si `[offset, offset + length)` tient dans le tampon.
    public func contains(offset: Int, length: Int) -> Bool {
        offset >= 0 && length >= 0 && offset <= count - length
    }

    /// Chaîne préfixée par sa longueur (uint16 LE), telle que Logic stocke les
    /// noms de canaux et de régions.
    ///
    /// Rejette tout ce qui n'est pas intégralement ASCII imprimable : c'est ce
    /// filtre qui distingue un vrai nom d'une coïncidence dans un blob binaire
    /// voisin. Rejette aussi les longueurs invraisemblables, pour ne pas
    /// interpréter du bruit comme une chaîne de plusieurs kilo-octets.
    public func lengthPrefixedASCII(at offset: Int, maxLength: Int) -> String? {
        guard let length = u16(at: offset), length > 0, length < maxLength else { return nil }
        let start = offset + 2
        guard contains(offset: start, length: length) else { return nil }

        let range = (base + start)..<(base + start + length)
        var scalars = [UInt8]()
        scalars.reserveCapacity(length)
        for index in range {
            let byte = data[index]
            guard byte >= 0x20, byte < 0x7F else { return nil }
            scalars.append(byte)
        }
        return String(decoding: scalars, as: UTF8.self)
    }

    /// Offsets de toutes les occurrences de `pattern`.
    ///
    /// Délègue à `Data.range(of:)`, qui descend dans une recherche optimisée,
    /// plutôt qu'à une boucle octet par octet en Swift.
    public func offsets(of pattern: Data) -> [Int] {
        guard !pattern.isEmpty, pattern.count <= count else { return [] }
        var result: [Int] = []
        var searchStart = base
        let end = data.endIndex
        while searchStart < end,
              let found = data.range(of: pattern, in: searchStart..<end) {
            result.append(data.distance(from: base, to: found.lowerBound))
            searchStart = data.index(after: found.lowerBound)
        }
        return result
    }
}
