import XCTest
@testable import VoicePresenceCore

final class ProjectDataParserTests: XCTestCase {

    func testExtractsChannelsWithSlotNameAndRouting() {
        let data = ProjectDataFixture.projectData(
            channels: [.init(slot: 0xa4, name: "voice verse 1", output: 0xe0),
                       .init(slot: 0xe0, name: "Verse bus", output: 0xa8),
                       .init(slot: 0xa8, name: "Voice bus")],
            regions: [])
        let parsed = ProjectDataParser.parse(ByteReader(data))

        XCTAssertEqual(parsed.channels.count, 3)
        XCTAssertEqual(parsed.channels[0xa4],
                       MixerChannel(slot: 0xa4, name: "voice verse 1", outputSlot: 0xe0))
        XCTAssertEqual(parsed.channels[0xe0]?.outputSlot, 0xa8)
        XCTAssertEqual(parsed.channels[0xa8]?.outputSlot, LogicFormat.unassignedSlot)
    }

    func testExtractsRegionNamesInFileOrderKeepingDuplicates() {
        let data = ProjectDataFixture.projectData(
            channels: [],
            regions: ["voice chorus", "voice chorus", "gratte verse#02.1"])
        let parsed = ProjectDataParser.parse(ByteReader(data))
        XCTAssertEqual(parsed.regionNames, ["voice chorus", "voice chorus", "gratte verse#02.1"])
    }

    func testIgnoresSignatureWithoutRoomForChunk() {
        var data = ProjectDataFixture.projectData(channels: [], regions: ["real"])
        data.append(LogicFormat.channelMagic)
        data.append(LogicFormat.regionMagic)
        let parsed = ProjectDataParser.parse(ByteReader(data))
        XCTAssertTrue(parsed.channels.isEmpty)
        XCTAssertEqual(parsed.regionNames, ["real"])
    }

    func testIgnoresChunkWhoseNameIsUnreadable() {
        // Chunk valide en taille, mais champ de nom laissé à zéro.
        var bytes = [UInt8](repeating: 0, count: ProjectDataFixture.channelChunkSize)
        for (index, byte) in LogicFormat.channelMagic.enumerated() { bytes[index] = byte }
        XCTAssertTrue(ProjectDataParser.parse(ByteReader(Data(bytes))).channels.isEmpty)
    }

    func testLastChunkWinsForDuplicateSlot() {
        // Deux chunks sur le même slot : le dernier lu l'emporte, comme dans un
        // dictionnaire. Documenté par un test pour que ce ne soit pas accidentel.
        let data = ProjectDataFixture.projectData(
            channels: [.init(slot: 0x10, name: "premier"), .init(slot: 0x10, name: "second")],
            regions: [])
        let parsed = ProjectDataParser.parse(ByteReader(data))
        XCTAssertEqual(parsed.channels.count, 1)
        XCTAssertEqual(parsed.channels[0x10]?.name, "second")
    }

    func testEmptyAndGarbageInputYieldEmptyResult() {
        XCTAssertTrue(ProjectDataParser.parse(ByteReader(Data())).channels.isEmpty)
        let garbage = Data((0..<4096).map { UInt8($0 % 251) })
        let parsed = ProjectDataParser.parse(ByteReader(garbage))
        // Rien ne garantit l'absence de signature fortuite, mais rien ne doit
        // planter et aucun nom non ASCII ne doit passer le filtre.
        for channel in parsed.channels.values {
            XCTAssertTrue(channel.name.allSatisfy { $0.isASCII })
        }
    }

    func testParsesFromFile() throws {
        let directory = try ProjectDataFixture.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ProjectData")
        try ProjectDataFixture.projectData(
            channels: [.init(slot: 0x10, name: "Voice bus")], regions: ["x"]).write(to: url)

        let parsed = try ProjectDataParser.parse(fileAt: url)
        XCTAssertEqual(parsed.channels[0x10]?.name, "Voice bus")
        XCTAssertEqual(parsed.regionNames, ["x"])
    }

    func testParsingMissingFileThrows() {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        XCTAssertThrowsError(try ProjectDataParser.parse(fileAt: missing))
    }

    func testComparableNameTrimsAndLowercases() {
        let channel = MixerChannel(slot: 1, name: "  Voice Bus  ", outputSlot: 0)
        XCTAssertEqual(channel.comparableName, "voice bus")
    }

    func testEmptyProjectDataConstant() {
        XCTAssertTrue(ProjectData.empty.channels.isEmpty)
        XCTAssertTrue(ProjectData.empty.regionNames.isEmpty)
    }
}
