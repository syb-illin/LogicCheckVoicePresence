import Foundation

/// Un canal alimentant le bus cherché.
public struct LinkedChannel: Identifiable, Hashable, Sendable {
    public var id: Int { slot }
    public let slot: Int
    public let name: String
    /// Régions attribuées de façon certaine à ce canal.
    public let regionCount: Int
    /// Le canal reçoit d'autres canaux : c'est un bus intermédiaire, pas une piste.
    public let isIntermediateBus: Bool

    public init(slot: Int, name: String, regionCount: Int, isIntermediateBus: Bool) {
        self.slot = slot
        self.name = name
        self.regionCount = regionCount
        self.isIntermediateBus = isIntermediateBus
    }

    public var hasAudio: Bool { regionCount > 0 }
}

/// Résultat de l'analyse d'un `ProjectData` pour un nom de bus donné.
public struct VoiceBusAnalysis: Sendable {
    /// Canaux dont le nom correspond au bus cherché.
    public let matchedBuses: [MixerChannel]
    /// Canaux alimentant ces bus, bus intermédiaires inclus, triés par nombre de
    /// régions décroissant.
    public let linkedChannels: [LinkedChannel]
    public let totalNamedChannels: Int
    public let totalRegions: Int
    /// Régions rattachées au bus sans pouvoir trancher le canal exact.
    public let ambiguousRegions: Int

    public init(matchedBuses: [MixerChannel],
                linkedChannels: [LinkedChannel],
                totalNamedChannels: Int,
                totalRegions: Int,
                ambiguousRegions: Int) {
        self.matchedBuses = matchedBuses
        self.linkedChannels = linkedChannels
        self.totalNamedChannels = totalNamedChannels
        self.totalRegions = totalRegions
        self.ambiguousRegions = ambiguousRegions
    }

    public static let empty = VoiceBusAnalysis(matchedBuses: [], linkedChannels: [],
                                               totalNamedChannels: 0, totalRegions: 0,
                                               ambiguousRegions: 0)

    public var busNames: [String] { matchedBuses.map(\.name) }
    public var hasBus: Bool { !matchedBuses.isEmpty }
    public var firmRegionsOnLinkedChannels: Int { linkedChannels.reduce(0) { $0 + $1.regionCount } }
    public var channelsWithAudio: Int { linkedChannels.filter(\.hasAudio).count }
}

/// Analyse un `ProjectData` : trouve le bus, remonte ses alimentations, rattache
/// les régions.
///
/// Composition de trois briques indépendantes et testables séparément —
/// ``ProjectDataParser`` (décodage), ``RoutingGraph`` (topologie),
/// ``RegionAttribution`` (rattachement) — qui n'ont aucune connaissance l'une de
/// l'autre.
public enum VoiceBusAnalyzer {

    public static func analyze(_ projectData: ProjectData, busName target: String) -> VoiceBusAnalysis {
        let graph = RoutingGraph(channels: projectData.channels)
        let busSlots = graph.slots(matching: target)

        guard !busSlots.isEmpty else {
            Log.routing.debug("Aucun bus correspondant parmi \(projectData.channels.count, privacy: .public) canaux")
            return VoiceBusAnalysis(matchedBuses: [],
                                    linkedChannels: [],
                                    totalNamedChannels: projectData.channels.count,
                                    totalRegions: projectData.regionNames.count,
                                    ambiguousRegions: 0)
        }

        let linkedSlots = graph.feeders(of: busSlots)
        let attribution = RegionAttribution.attribute(regionNames: projectData.regionNames,
                                                      channels: projectData.channels,
                                                      linkedSlots: linkedSlots)

        let linked = linkedSlots
            .compactMap { slot -> LinkedChannel? in
                guard let channel = graph.channel(at: slot) else { return nil }
                return LinkedChannel(slot: slot,
                                     name: channel.name,
                                     regionCount: attribution.firmCount(for: slot),
                                     isIntermediateBus: graph.isIntermediateBus(slot))
            }
            .sorted {
                ($1.regionCount, $0.name.lowercased()) < ($0.regionCount, $1.name.lowercased())
            }

        Log.routing.debug("Bus trouvé, \(linked.count, privacy: .public) canaux liés, \(attribution.totalFirm, privacy: .public) régions fermes, \(attribution.ambiguousCount, privacy: .public) ambiguës")

        return VoiceBusAnalysis(matchedBuses: busSlots.compactMap { graph.channel(at: $0) },
                                linkedChannels: linked,
                                totalNamedChannels: projectData.channels.count,
                                totalRegions: projectData.regionNames.count,
                                ambiguousRegions: attribution.ambiguousCount)
    }

    public static func analyze(fileAt url: URL, busName target: String) throws -> VoiceBusAnalysis {
        analyze(try ProjectDataParser.parse(fileAt: url), busName: target)
    }
}
