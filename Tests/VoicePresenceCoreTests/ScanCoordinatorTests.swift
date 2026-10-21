import XCTest
@testable import VoicePresenceCore

final class ScanCoordinatorTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = try ProjectDataFixture.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func coordinator(limit: Int? = nil) -> ScanCoordinator {
        ScanCoordinator(locator: ProjectLocator(),
                        inspector: ProjectInspector(locator: ProjectLocator(),
                                                    audioAnalyzer: StubAudioAnalyzer()),
                        concurrencyLimit: limit)
    }

    private func makeProjects(_ count: Int, withBus: Bool = true) throws {
        let data = ProjectDataFixture.projectData(
            channels: withBus
                ? [.init(slot: 0x10, name: "Voice bus"),
                   .init(slot: 0x14, name: "voice verse 1", output: 0x10)]
                : [.init(slot: 0x10, name: "Drum bus")],
            regions: withBus ? ["voice verse 1"] : ["kick"])
        for index in 0..<count {
            try ProjectDataFixture.makeBundle(named: String(format: "p%03d", index),
                                              in: root, alternatives: ["000": data])
        }
    }

    private func collect(_ stream: AsyncStream<ScanEvent>) async -> [ScanEvent] {
        var events: [ScanEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    func testEmitsDiscoveredThenInspectedThenFinished() async throws {
        try makeProjects(3)
        let events = await collect(coordinator().scan(root: root, busName: "voice bus"))

        guard case .discovered(let total) = events.first else {
            return XCTFail("premier événement attendu : .discovered")
        }
        XCTAssertEqual(total, 3)

        guard case .finished(_, let completed) = events.last else {
            return XCTFail("dernier événement attendu : .finished")
        }
        XCTAssertEqual(completed, 3)

        let inspected = events.compactMap { event -> ProjectInspection? in
            if case .inspected(let inspection, _, _) = event { return inspection }
            return nil
        }
        XCTAssertEqual(inspected.count, 3)
        XCTAssertTrue(inspected.allSatisfy { $0.verdict == .busWithAudio })
    }

    func testProgressCountsAreMonotonicAndComplete() async throws {
        try makeProjects(12)
        let events = await collect(coordinator(limit: 4).scan(root: root, busName: "voice bus"))

        var seen: [Int] = []
        for event in events {
            if case .inspected(_, let completed, let total) = event {
                XCTAssertEqual(total, 12)
                seen.append(completed)
            }
        }
        XCTAssertEqual(seen, Array(1...12), "la progression doit être strictement croissante")
    }

    func testEmptyFolderFinishesImmediately() async {
        let events = await collect(coordinator().scan(root: root, busName: "voice bus"))
        XCTAssertEqual(events.count, 2)
        if case .discovered(let total) = events[0] { XCTAssertEqual(total, 0) }
        else { XCTFail("attendu .discovered") }
        if case .finished(_, let completed) = events[1] { XCTAssertEqual(completed, 0) }
        else { XCTFail("attendu .finished") }
    }

    func testEveryProjectIsInspectedExactlyOnce() async throws {
        try makeProjects(25)
        let events = await collect(coordinator(limit: 3).scan(root: root, busName: "voice bus"))
        let names = events.compactMap { event -> String? in
            if case .inspected(let inspection, _, _) = event { return inspection.name }
            return nil
        }
        XCTAssertEqual(names.count, 25)
        XCTAssertEqual(Set(names).count, 25, "aucun projet ne doit être inspecté deux fois")
    }

    func testResultsRespectBusName() async throws {
        try makeProjects(2, withBus: false)
        let events = await collect(coordinator().scan(root: root, busName: "voice bus"))
        let verdicts = events.compactMap { event -> Verdict? in
            if case .inspected(let inspection, _, _) = event { return inspection.verdict }
            return nil
        }
        XCTAssertEqual(verdicts, [.noBus, .noBus])
    }

    /// Abandonner la consommation du flux doit arrêter le travail, pas le
    /// laisser tourner en arrière-plan.
    func testCancellationStopsEarly() async throws {
        try makeProjects(60)
        let stream = coordinator(limit: 2).scan(root: root, busName: "voice bus")

        var received = 0
        for await event in stream {
            if case .inspected = event {
                received += 1
                if received == 3 { break }
            }
        }
        XCTAssertEqual(received, 3)
        // Sortir de la boucle déclenche onTermination : rien de plus à attendre.
    }

    func testDefaultConcurrencyLimitIsSane() {
        let limit = ScanCoordinator.defaultConcurrencyLimit
        XCTAssertGreaterThanOrEqual(limit, 2)
        XCTAssertLessThanOrEqual(limit, 12)
    }

    func testConcurrencyLimitGreaterThanProjectCountIsHandled() async throws {
        try makeProjects(2)
        let events = await collect(coordinator(limit: 32).scan(root: root, busName: "voice bus"))
        guard case .finished(_, let completed) = events.last else {
            return XCTFail("attendu .finished")
        }
        XCTAssertEqual(completed, 2)
    }

    func testSingleProjectWithLimitOne() async throws {
        try makeProjects(1)
        let events = await collect(coordinator(limit: 1).scan(root: root, busName: "voice bus"))
        guard case .finished(_, let completed) = events.last else {
            return XCTFail("attendu .finished")
        }
        XCTAssertEqual(completed, 1)
    }
}
