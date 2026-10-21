import Foundation

/// Graphe de routage du mixeur : qui envoie son signal vers qui.
///
/// Dans Logic, un bus nommé reçoit rarement les pistes directement. Un cas réel
/// typique est à deux niveaux :
///
/// ```
/// voice verse 1 ─┐
/// voice verse 2 ─┼─> Verse bus  ─┐
/// voice verse 3 ─┘               ├─> Voice bus
/// voice chorus L ┐               │
/// voice chorus R ┼─> Chorus bus ─┘
/// voice chorus C ┘
/// ```
///
/// Chercher les canaux pointant *directement* sur `Voice bus` ne trouverait que
/// deux bus intermédiaires et zéro piste, et conclurait à tort que le bus n'a
/// pas d'audio. D'où la fermeture transitive.
public struct RoutingGraph: Sendable {
    private let channels: [Int: MixerChannel]
    /// Slots qui reçoivent au moins un autre canal : ce sont des bus, pas des
    /// pistes sources.
    public let receivingSlots: Set<Int>

    public init(channels: [Int: MixerChannel]) {
        self.channels = channels
        self.receivingSlots = Set(channels.values.map(\.outputSlot))
    }

    public var allChannels: [Int: MixerChannel] { channels }

    public func channel(at slot: Int) -> MixerChannel? { channels[slot] }

    /// Slots des canaux dont le nom contient `target`, casse ignorée.
    public func slots(matching target: String) -> [Int] {
        let needle = target.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return channels.values
            .filter { $0.comparableName.contains(needle) }
            .map(\.slot)
            .sorted()
    }

    /// Tous les canaux qui alimentent `destinations`, directement ou par
    /// transitivité, en excluant les destinations elles-mêmes.
    ///
    /// Résistant aux cycles : un canal déjà atteint n'est jamais revisité, donc
    /// un routage circulaire — que Logic n'autorise pas mais qu'un fichier
    /// corrompu peut contenir — termine au lieu de boucler.
    public func feeders(of destinations: [Int]) -> Set<Int> {
        guard !destinations.isEmpty else { return [] }

        var reached = Set(destinations)
        var frontier = Set(destinations)

        // Index inversé construit une fois : sortie -> canaux qui y entrent.
        // Évite de réexaminer tous les canaux à chaque tour.
        var incoming: [Int: [Int]] = [:]
        incoming.reserveCapacity(channels.count)
        for channel in channels.values {
            incoming[channel.outputSlot, default: []].append(channel.slot)
        }

        while let slot = frontier.popFirst() {
            for candidate in incoming[slot] ?? [] where !reached.contains(candidate) {
                reached.insert(candidate)
                frontier.insert(candidate)
            }
        }

        return reached.subtracting(destinations)
    }

    /// Vrai si le canal reçoit d'autres canaux : bus intermédiaire, pas piste.
    public func isIntermediateBus(_ slot: Int) -> Bool { receivingSlots.contains(slot) }
}
