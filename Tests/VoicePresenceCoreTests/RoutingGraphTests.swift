import XCTest
@testable import VoicePresenceCore

final class RoutingGraphTests: XCTestCase {

    private func graph(_ specs: [(Int, String, Int)]) -> RoutingGraph {
        var channels: [Int: MixerChannel] = [:]
        for (slot, name, output) in specs {
            channels[slot] = MixerChannel(slot: slot, name: name, outputSlot: output)
        }
        return RoutingGraph(channels: channels)
    }

    // MARK: - Recherche du bus

    func testMatchesBySubstringIgnoringCase() {
        let g = graph([(0x10, "My VOICE BUS left", 0), (0x14, "Drum bus", 0)])
        XCTAssertEqual(g.slots(matching: "voice bus"), [0x10])
        XCTAssertEqual(g.slots(matching: "VOICE"), [0x10])
        XCTAssertEqual(g.slots(matching: "bus").sorted(), [0x10, 0x14])
    }

    func testMatchesTrimsTargetAndRejectsEmpty() {
        let g = graph([(0x10, "Voice bus", 0)])
        XCTAssertEqual(g.slots(matching: "  voice bus  "), [0x10])
        XCTAssertTrue(g.slots(matching: "").isEmpty)
        XCTAssertTrue(g.slots(matching: "   ").isEmpty)
    }

    func testReturnsSortedSlotsForMultipleMatches() {
        let g = graph([(0x30, "Voice bus 2", 0), (0x10, "Voice bus", 0)])
        XCTAssertEqual(g.slots(matching: "voice bus"), [0x10, 0x30])
    }

    func testNoMatchYieldsEmpty() {
        XCTAssertTrue(graph([(0x10, "Drum bus", 0)]).slots(matching: "voice bus").isEmpty)
    }

    // MARK: - Fermeture transitive

    func testDirectFeeders() {
        let g = graph([(0x10, "Voice bus", 0), (0x14, "voice verse", 0x10), (0x18, "kick", 0x20)])
        XCTAssertEqual(g.feeders(of: [0x10]), [0x14])
    }

    /// Le cas qui invalide une recherche directe : deux niveaux de bus.
    func testTransitiveFeedersAcrossTwoLevels() {
        let g = graph([(0xa8, "Voice bus", 0),
                       (0xe0, "Verse bus", 0xa8),
                       (0xe8, "Chorus bus", 0xa8),
                       (0xa4, "voice verse 1", 0xe0),
                       (0xc0, "voice chorus L", 0xe8)])
        XCTAssertEqual(g.feeders(of: [0xa8]), [0xe0, 0xe8, 0xa4, 0xc0])
    }

    func testTransitiveFeedersAcrossThreeLevels() {
        let g = graph([(0x10, "Voice bus", 0),
                       (0x14, "Chorus bus", 0x10),
                       (0x18, "Harmo bus", 0x14),
                       (0x1c, "voice harmo", 0x18)])
        XCTAssertEqual(g.feeders(of: [0x10]), [0x14, 0x18, 0x1c])
    }

    func testDestinationsAreExcludedFromFeeders() {
        let g = graph([(0x10, "Voice bus", 0), (0x14, "Voice bus 2", 0x10)])
        // 0x14 alimente 0x10 mais est lui-même une destination : exclu si passé.
        XCTAssertEqual(g.feeders(of: [0x10, 0x14]), [])
    }

    func testEmptyDestinationsYieldNoFeeders() {
        XCTAssertTrue(graph([(0x10, "a", 0)]).feeders(of: []).isEmpty)
    }

    func testUnrelatedBranchIsNotIncluded() {
        let g = graph([(0x10, "Voice bus", 0), (0x20, "Drum bus", 0),
                       (0x24, "kick", 0x20), (0x28, "snare", 0x20)])
        XCTAssertTrue(g.feeders(of: [0x10]).isEmpty)
    }

    /// Robustesse : Logic ne crée pas de cycle, un fichier corrompu peut.
    /// La fonction doit terminer.
    func testCycleTerminates() {
        let g = graph([(0x10, "Voice bus", 0x14), (0x14, "A", 0x18), (0x18, "B", 0x14)])
        // Personne n'envoie vers 0x10 : aucun alimentant.
        XCTAssertEqual(g.feeders(of: [0x10]), [])
        // 0x14 reçoit 0x10 (le bus lui-même) et 0x18, qui boucle avec lui.
        XCTAssertEqual(g.feeders(of: [0x14]), [0x10, 0x18])
    }

    func testSelfLoopTerminates() {
        let g = graph([(0x10, "Voice bus", 0x10)])
        XCTAssertTrue(g.feeders(of: [0x10]).isEmpty)
    }

    func testLongChainIsFullyTraversed() {
        // Chaîne de 200 maillons : vérifie qu'il n'y a pas de limite de
        // profondeur cachée ni de débordement de pile.
        var specs: [(Int, String, Int)] = [(0, "Voice bus", -1)]
        for index in 1...200 { specs.append((index, "c\(index)", index - 1)) }
        let g = graph(specs)
        XCTAssertEqual(g.feeders(of: [0]).count, 200)
    }

    // MARK: - Bus intermédiaires

    func testIntermediateBusDetection() {
        let g = graph([(0x10, "Voice bus", 0), (0x14, "Verse bus", 0x10), (0x18, "piste", 0x14)])
        XCTAssertTrue(g.isIntermediateBus(0x14))
        XCTAssertFalse(g.isIntermediateBus(0x18))
    }

    func testChannelLookup() {
        let g = graph([(0x10, "Voice bus", 0)])
        XCTAssertEqual(g.channel(at: 0x10)?.name, "Voice bus")
        XCTAssertNil(g.channel(at: 0x99))
        XCTAssertEqual(g.allChannels.count, 1)
    }
}
