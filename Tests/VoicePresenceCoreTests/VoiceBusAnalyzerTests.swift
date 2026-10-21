import XCTest
@testable import VoicePresenceCore

/// Tests d'intégration des trois briques d'analyse, sur des `ProjectData`
/// synthétiques reproduisant des topologies observées dans de vrais projets.
final class VoiceBusAnalyzerTests: XCTestCase {

    private func analyze(_ channels: [ProjectDataFixture.ChannelSpec],
                         _ regions: [String],
                         target: String = "voice bus") -> VoiceBusAnalysis {
        let data = ProjectDataFixture.projectData(channels: channels, regions: regions)
        return VoiceBusAnalyzer.analyze(ProjectDataParser.parse(ByteReader(data)), busName: target)
    }

    // MARK: - Absence de bus

    func testNoBusWhenTargetAbsent() {
        let analysis = analyze([.init(slot: 0x10, name: "Drum bus"),
                                .init(slot: 0x14, name: "kick", output: 0x10)],
                               ["kick"])
        XCTAssertFalse(analysis.hasBus)
        XCTAssertTrue(analysis.matchedBuses.isEmpty)
        XCTAssertTrue(analysis.linkedChannels.isEmpty)
        XCTAssertEqual(analysis.totalNamedChannels, 2)
        XCTAssertEqual(analysis.totalRegions, 1)
        XCTAssertEqual(analysis.ambiguousRegions, 0)
    }

    // MARK: - Bus orphelin

    func testOrphanBusHasNoLinkedChannels() {
        let analysis = analyze([.init(slot: 0x20, name: "Voice bus"),
                                .init(slot: 0x24, name: "kick", output: 0x28),
                                .init(slot: 0x28, name: "Drum bus")],
                               ["kick"])
        XCTAssertTrue(analysis.hasBus)
        XCTAssertTrue(analysis.linkedChannels.isEmpty)
        XCTAssertEqual(analysis.busNames, ["Voice bus"])
    }

    // MARK: - Routage direct

    func testDirectRoutingWithFirmRegions() throws {
        let analysis = analyze([.init(slot: 0x20, name: "Voice bus"),
                                .init(slot: 0x24, name: "voice verse 1", output: 0x20)],
                               ["voice verse 1", "voice verse 1#02", "voice verse 1#02.3"])

        XCTAssertEqual(analysis.linkedChannels.count, 1)
        let channel = try XCTUnwrap(analysis.linkedChannels.first)
        XCTAssertEqual(channel.name, "voice verse 1")
        XCTAssertEqual(channel.regionCount, 3)
        XCTAssertFalse(channel.isIntermediateBus)
        XCTAssertTrue(channel.hasAudio)
        XCTAssertEqual(analysis.firmRegionsOnLinkedChannels, 3)
        XCTAssertEqual(analysis.channelsWithAudio, 1)
    }

    // MARK: - Hiérarchie à deux niveaux

    /// Topologie réelle : aucune piste ne pointe directement sur le bus cible.
    func testTwoLevelHierarchy() {
        let analysis = analyze([.init(slot: 0xa8, name: "Voice bus"),
                                .init(slot: 0xe0, name: "Verse bus", output: 0xa8),
                                .init(slot: 0xe8, name: "Chorus bus", output: 0xa8),
                                .init(slot: 0xa4, name: "voice verse 1", output: 0xe0),
                                .init(slot: 0xb0, name: "voice verse 2", output: 0xe0),
                                .init(slot: 0xc0, name: "voice chorus L", output: 0xe8)],
                               ["voice verse 1", "voice verse 2", "voice chorus L"])

        XCTAssertEqual(analysis.linkedChannels.count, 5)
        let byName = Dictionary(uniqueKeysWithValues: analysis.linkedChannels.map { ($0.name, $0) })
        XCTAssertEqual(byName["voice verse 1"]?.regionCount, 1)
        XCTAssertEqual(byName["voice verse 2"]?.regionCount, 1)
        XCTAssertEqual(byName["voice chorus L"]?.regionCount, 1)
        XCTAssertEqual(byName["Verse bus"]?.isIntermediateBus, true)
        XCTAssertEqual(byName["Chorus bus"]?.isIntermediateBus, true)
        XCTAssertEqual(byName["voice verse 1"]?.isIntermediateBus, false)
        XCTAssertEqual(analysis.firmRegionsOnLinkedChannels, 3)
    }

    // MARK: - Tri

    func testLinkedChannelsSortedByRegionCountThenName() {
        let analysis = analyze([.init(slot: 0x10, name: "Voice bus"),
                                .init(slot: 0x14, name: "zz piste", output: 0x10),
                                .init(slot: 0x18, name: "aa piste", output: 0x10),
                                .init(slot: 0x1c, name: "riche", output: 0x10)],
                               ["riche", "riche#01", "zz piste", "aa piste"])

        XCTAssertEqual(analysis.linkedChannels.map(\.name), ["riche", "aa piste", "zz piste"])
    }

    // MARK: - Ambiguïté

    func testAmbiguousRegionsAreReportedWithoutFirmCount() {
        let analysis = analyze([.init(slot: 0x10, name: "Voice bus"),
                                .init(slot: 0x14, name: "Voice chorus a", output: 0x10),
                                .init(slot: 0x18, name: "Voice chorus b", output: 0x10)],
                               ["Voice chorus", "Voice chorus.1"])

        XCTAssertEqual(analysis.ambiguousRegions, 2)
        XCTAssertEqual(analysis.firmRegionsOnLinkedChannels, 0)
        XCTAssertEqual(analysis.channelsWithAudio, 0)
    }

    // MARK: - Bus multiples

    func testMultipleMatchingBusesAreAllReported() {
        let analysis = analyze([.init(slot: 0x10, name: "Voice bus"),
                                .init(slot: 0x14, name: "Voice bus 2"),
                                .init(slot: 0x18, name: "voice verse 1", output: 0x14)],
                               ["voice verse 1"])

        XCTAssertEqual(analysis.matchedBuses.map(\.slot), [0x10, 0x14])
        XCTAssertEqual(analysis.busNames.count, 2)
        XCTAssertEqual(analysis.linkedChannels.count, 1)
    }

    // MARK: - Entrées dégénérées

    func testEmptyProjectDataYieldsNoBus() {
        let analysis = VoiceBusAnalyzer.analyze(.empty, busName: "voice bus")
        XCTAssertFalse(analysis.hasBus)
        XCTAssertEqual(analysis.totalNamedChannels, 0)
    }

    func testEmptyAnalysisConstant() {
        XCTAssertFalse(VoiceBusAnalysis.empty.hasBus)
        XCTAssertEqual(VoiceBusAnalysis.empty.firmRegionsOnLinkedChannels, 0)
        XCTAssertEqual(VoiceBusAnalysis.empty.channelsWithAudio, 0)
        XCTAssertTrue(VoiceBusAnalysis.empty.busNames.isEmpty)
    }

    func testAnalyzeFromFile() throws {
        let directory = try ProjectDataFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ProjectData")
        try ProjectDataFixture.projectData(
            channels: [.init(slot: 0x10, name: "Voice bus"),
                       .init(slot: 0x14, name: "voice verse 1", output: 0x10)],
            regions: ["voice verse 1"]).write(to: url)

        let analysis = try VoiceBusAnalyzer.analyze(fileAt: url, busName: "voice bus")
        XCTAssertEqual(analysis.firmRegionsOnLinkedChannels, 1)
    }

    func testAnalyzeFromMissingFileThrows() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        XCTAssertThrowsError(try VoiceBusAnalyzer.analyze(fileAt: missing, busName: "voice bus"))
    }
}
