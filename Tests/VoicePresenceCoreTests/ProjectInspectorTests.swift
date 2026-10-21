import XCTest
@testable import VoicePresenceCore

/// Bout en bout sur des bundles réels posés sur disque, avec un analyseur audio
/// factice : la chaîne complète est exercée sans dépendre du classifieur système.
final class ProjectInspectorTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = try ProjectDataFixture.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func inspector(audioFiles: [URL] = []) -> ProjectInspector {
        ProjectInspector(locator: ProjectLocator(),
                         audioAnalyzer: StubAudioAnalyzer(files: audioFiles))
    }

    /// Reproduit « bus voice présent, aucun audio » observé sur un projet réel.
    func testBusWithoutAudio() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "no audio", in: root,
            alternatives: ["000": ProjectDataFixture.projectData(
                channels: [.init(slot: 0xc4, name: "voice bus"),
                           .init(slot: 0xb4, name: "Audio 1", output: 0xc4),
                           .init(slot: 0xb8, name: "Audio 2", output: 0xc4)],
                regions: [])])

        let result = inspector().inspect(project: bundle, busName: "voice bus")

        XCTAssertEqual(result.baseVerdict, .busNoAudio)
        XCTAssertEqual(result.verdict, .busNoAudio)
        XCTAssertEqual(result.name, "no audio")
        XCTAssertEqual(result.busLabel, "voice bus")
        XCTAssertEqual(result.linkedChannelCount, 2)
        XCTAssertEqual(result.channelsWithAudio, 0)
        XCTAssertEqual(result.firmRegions, 0)
        XCTAssertEqual(result.audioFileCount, 0)
        XCTAssertNil(result.failure)
        XCTAssertNil(result.audioNote)
        XCTAssertFalse(result.needsAudioAnalysis)
    }

    /// Reproduit « bus voice avec audio via bus intermédiaires ».
    func testBusWithAudioThroughIntermediateBuses() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "with audio", in: root,
            alternatives: ["000": ProjectDataFixture.projectData(
                channels: [.init(slot: 0xa8, name: "Voice bus"),
                           .init(slot: 0xe0, name: "Verse bus", output: 0xa8),
                           .init(slot: 0xe8, name: "Chorus bus", output: 0xa8),
                           .init(slot: 0xa4, name: "voice verse 1", output: 0xe0),
                           .init(slot: 0xc0, name: "voice chorus 75 L", output: 0xe8)],
                regions: ["voice verse 1", "voice verse 1#05.1", "voice chorus 75 L"])],
            audioFileNames: ["voice verse 1#05.wav"])

        let files = [bundle.appendingPathComponent("Media/Audio Files/voice verse 1#05.wav")]
        let result = inspector(audioFiles: files).inspect(project: bundle, busName: "voice bus")

        XCTAssertEqual(result.verdict, .busWithAudio)
        XCTAssertEqual(result.linkedChannelCount, 4)
        XCTAssertEqual(result.firmRegions, 3)
        XCTAssertEqual(result.channelsWithAudio, 2)
        XCTAssertEqual(result.audioFileCount, 1)
    }

    /// Régions nommées d'après le projet, canaux nommés « Voice … » : rien ne
    /// concorde alors que l'audio existe. C'est le cas qui justifie l'étage 3.
    func testUndecidableProjectIsFlagged() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "undecidable", in: root,
            alternatives: ["000": ProjectDataFixture.projectData(
                channels: [.init(slot: 0x10, name: "Voice bus"),
                           .init(slot: 0x14, name: "Voice verse 50 L", output: 0x10)],
                regions: ["clear the air_3#02", "clear the air_3#02.1"])],
            audioFileNames: ["clear the air_3#02.wav", "clear the air_1#01.wav"])

        let files = ["clear the air_3#02.wav", "clear the air_1#01.wav"]
            .map { bundle.appendingPathComponent("Media/Audio Files/\($0)") }
        let result = inspector(audioFiles: files).inspect(project: bundle, busName: "voice bus")

        XCTAssertEqual(result.verdict, .undecidable)
        XCTAssertTrue(result.needsAudioAnalysis)
        XCTAssertEqual(result.audioFileCount, 2)
    }

    func testUndecidableBecomesProbableWhenVocalDetected() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "revised", in: root,
            alternatives: ["000": ProjectDataFixture.projectData(
                channels: [.init(slot: 0x10, name: "Voice bus"),
                           .init(slot: 0x14, name: "Voice verse 1", output: 0x10)],
                regions: ["Maserati vox1 and vocal rider#01"])],
            audioFileNames: ["Maserati vox1 and vocal rider#01.aif"])

        let files = [bundle.appendingPathComponent(
            "Media/Audio Files/Maserati vox1 and vocal rider#01.aif")]
        var result = inspector(audioFiles: files).inspect(project: bundle, busName: "voice bus")
        XCTAssertEqual(result.verdict, .undecidable)

        result.audioAnalysis = AudioAnalysisReport(files: [.stub(vocalConfidence: 0.93)])
        XCTAssertEqual(result.verdict, .busProbableAudio)
        XCTAssertTrue(result.audioNote?.contains("voix détectée") == true)
        XCTAssertFalse(result.needsAudioAnalysis)
    }

    func testUnreadableProjectWithoutProjectData() throws {
        let bundle = try ProjectDataFixture.makeBundle(named: "broken", in: root)
        let result = inspector().inspect(project: bundle, busName: "voice bus")

        XCTAssertEqual(result.verdict, .unreadable)
        XCTAssertEqual(result.alternative, "—")
        XCTAssertNotNil(result.failure)
        XCTAssertTrue(result.analysis.linkedChannels.isEmpty)
    }

    func testProjectWithoutMatchingBus() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "instrumental", in: root,
            alternatives: ["000": ProjectDataFixture.projectData(
                channels: [.init(slot: 0x10, name: "Drum bus"),
                           .init(slot: 0x14, name: "kick", output: 0x10)],
                regions: ["kick"])])

        let result = inspector().inspect(project: bundle, busName: "voice bus")
        XCTAssertEqual(result.verdict, .noBus)
        XCTAssertEqual(result.busLabel, "—")
    }

    func testOrphanBus() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "orphan", in: root,
            alternatives: ["000": ProjectDataFixture.projectData(
                channels: [.init(slot: 0x10, name: "Voice bus")], regions: [])])

        XCTAssertEqual(inspector().inspect(project: bundle, busName: "voice bus").verdict,
                       .busOrphan)
    }

    func testAlternativeIsReported() throws {
        let data = ProjectDataFixture.projectData(
            channels: [.init(slot: 0x10, name: "Voice bus")], regions: [])
        let bundle = try ProjectDataFixture.makeBundle(
            named: "alts", in: root, alternatives: ["000": data, "003": data])
        XCTAssertEqual(inspector().inspect(project: bundle, busName: "voice bus").alternative,
                       "003")
    }
}
