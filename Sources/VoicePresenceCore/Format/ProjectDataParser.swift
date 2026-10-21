import Foundation

/// Une tranche du mixeur, telle que décodée depuis un chunk `ivnE`.
public struct MixerChannel: Hashable, Sendable {
    /// Identifiant interne du canal.
    public let slot: Int
    /// Nom personnalisé affiché dans le mixeur.
    public let name: String
    /// Slot du canal vers lequel la sortie est routée.
    /// `LogicFormat.unassignedSlot` quand aucune sortie n'est assignée.
    public let outputSlot: Int

    public init(slot: Int, name: String, outputSlot: Int) {
        self.slot = slot
        self.name = name
        self.outputSlot = outputSlot
    }

    /// Nom normalisé pour comparaison : sans espaces de bord, en minuscules.
    public var comparableName: String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// Contenu décodé d'un `ProjectData`.
public struct ProjectData: Sendable {
    /// Canaux indexés par slot.
    public let channels: [Int: MixerChannel]
    /// Noms des régions audio, dans l'ordre du fichier. Les doublons sont
    /// conservés : deux régions distinctes peuvent porter le même nom.
    public let regionNames: [String]

    public init(channels: [Int: MixerChannel], regionNames: [String]) {
        self.channels = channels
        self.regionNames = regionNames
    }

    public static let empty = ProjectData(channels: [:], regionNames: [])
}

/// Décodage d'un `ProjectData` en canaux et régions.
///
/// Sans état, sans effet de bord : une fonction du tampon vers la structure.
/// Tout est vérifié aux bornes via ``ByteReader`` — un fichier tronqué, d'une
/// autre version de Logic, ou carrément d'un autre format, produit un résultat
/// partiel ou vide, jamais un plantage.
public enum ProjectDataParser {

    /// Décode un tampon déjà en mémoire.
    public static func parse(_ reader: ByteReader) -> ProjectData {
        let state = Log.signposter.beginInterval("parse", id: Log.signposter.makeSignpostID())
        defer { Log.signposter.endInterval("parse", state) }

        let channels = parseChannels(reader)
        let regions = parseRegionNames(reader)

        Log.parsing.debug("Décodé \(channels.count, privacy: .public) canaux, \(regions.count, privacy: .public) régions sur \(reader.count, privacy: .public) octets")
        return ProjectData(channels: channels, regionNames: regions)
    }

    /// Décode un fichier. Le mappage mémoire évite de charger plusieurs Mo par
    /// projet quand seuls quelques milliers d'octets sont réellement lus.
    public static func parse(fileAt url: URL) throws -> ProjectData {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return parse(ByteReader(data))
    }

    // MARK: - Détail

    static func parseChannels(_ reader: ByteReader) -> [Int: MixerChannel] {
        var channels: [Int: MixerChannel] = [:]
        for offset in reader.offsets(of: LogicFormat.channelMagic) {
            guard reader.contains(offset: offset, length: LogicFormat.channelMinimumSize) else {
                // Signature en fin de fichier sans chunk derrière : du bruit.
                continue
            }
            guard let slot = reader.u16(at: offset + LogicFormat.channelSlotOffset),
                  let outputSlot = reader.u16(at: offset + LogicFormat.channelOutputOffset),
                  let name = reader.lengthPrefixedASCII(at: offset + LogicFormat.channelNameOffset,
                                                        maxLength: LogicFormat.maximumNameLength)
            else { continue }

            // Les canaux sans nom personnalisé ne servent à rien ici : ils ne
            // peuvent être ni la cible recherchée ni une piste identifiable.
            channels[slot] = MixerChannel(slot: slot, name: name, outputSlot: outputSlot)
        }
        return channels
    }

    static func parseRegionNames(_ reader: ByteReader) -> [String] {
        var names: [String] = []
        for offset in reader.offsets(of: LogicFormat.regionMagic) {
            guard reader.contains(offset: offset, length: LogicFormat.regionMinimumSize) else { continue }
            if let name = reader.lengthPrefixedASCII(at: offset + LogicFormat.regionNameOffset,
                                                     maxLength: LogicFormat.maximumNameLength) {
                names.append(name)
            }
        }
        return names
    }
}
