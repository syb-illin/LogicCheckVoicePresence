import XCTest
@testable import VoicePresenceCore

final class ProjectLocatorTests: XCTestCase {

    private var root: URL!
    private let locator = ProjectLocator()

    override func setUpWithError() throws {
        root = try ProjectDataFixture.temporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Découverte

    func testFindsProjectsSortedNaturally() throws {
        for name in ["zebra", "Alpha", "projet 10", "projet 2"] {
            try ProjectDataFixture.makeBundle(named: name, in: root, alternatives: ["000": Data()])
        }
        let found = locator.projects(under: root)
            .map { $0.deletingPathExtension().lastPathComponent }
        // Tri naturel : "projet 2" avant "projet 10", contrairement à l'ordre
        // lexicographique.
        XCTAssertEqual(found, ["Alpha", "projet 2", "projet 10", "zebra"])
    }

    func testFindsProjectsInNestedDirectories() throws {
        let nested = root.appendingPathComponent("a/b/c", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try ProjectDataFixture.makeBundle(named: "buried", in: nested, alternatives: ["000": Data()])
        XCTAssertEqual(locator.projects(under: root).count, 1)
    }

    func testPassingBundleDirectlyReturnsItAlone() throws {
        let bundle = try ProjectDataFixture.makeBundle(named: "solo", in: root,
                                                       alternatives: ["000": Data()])
        XCTAssertEqual(locator.projects(under: bundle), [bundle])
    }

    /// Un bundle contient des sous-dossiers : ils ne doivent jamais être
    /// parcourus, sans quoi un corpus de plusieurs centaines de projets
    /// coûterait des minutes.
    func testDoesNotDescendIntoBundles() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "outer", in: root, alternatives: ["000": Data()])
        // Piège : un dossier d'extension .logicx à l'intérieur du bundle.
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Media/inner.logicx", isDirectory: true),
            withIntermediateDirectories: true)
        XCTAssertEqual(locator.projects(under: root), [bundle])
    }

    func testIgnoresOtherDirectories() throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("song.band", isDirectory: true),
            withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        XCTAssertTrue(locator.projects(under: root).isEmpty)
    }

    func testUnreadableRootYieldsEmpty() {
        XCTAssertTrue(locator.projects(under: root.appendingPathComponent("absent")).isEmpty)
    }

    func testEmptyRootYieldsEmpty() {
        XCTAssertTrue(locator.projects(under: root).isEmpty)
    }

    // MARK: - Choix de l'alternative

    func testPicksMostRecentAlternative() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "multi", in: root,
            alternatives: ["000": Data([1]), "001": Data([2]), "002": Data([3])])
        XCTAssertEqual(locator.latestProjectData(in: bundle)?.alternative, "002")

        // Rendre la première plus récente doit inverser le choix.
        try ProjectDataFixture.touch(bundle: bundle, alternative: "000",
                                     date: Date(timeIntervalSince1970: 5_000_000))
        XCTAssertEqual(locator.latestProjectData(in: bundle)?.alternative, "000")
    }

    /// Les sauvegardes sont plus récentes que les alternatives dans cette
    /// fixture : elles ne doivent pas pour autant être choisies.
    func testIgnoresProjectFileBackups() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "backed up", in: root, alternatives: ["000": Data([1])])
        try ProjectDataFixture.addBackup(to: bundle, alternative: "000", data: Data([9]))

        let picked = try XCTUnwrap(locator.latestProjectData(in: bundle))
        XCTAssertEqual(picked.alternative, "000")
        XCTAssertFalse(picked.url.path.contains("Backups"))
    }

    func testFallsBackToLegacyRootProjectData() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "legacy", in: root, legacyProjectData: Data([1]))
        let picked = try XCTUnwrap(locator.latestProjectData(in: bundle))
        XCTAssertEqual(picked.alternative, "—")
        XCTAssertEqual(picked.url.lastPathComponent, "ProjectData")
    }

    func testAlternativesTakePrecedenceOverLegacyFile() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "both", in: root, alternatives: ["000": Data([1])],
            legacyProjectData: Data([9]))
        XCTAssertEqual(locator.latestProjectData(in: bundle)?.alternative, "000")
    }

    func testReturnsNilWhenNoProjectDataAnywhere() throws {
        let bundle = try ProjectDataFixture.makeBundle(named: "empty", in: root)
        XCTAssertNil(locator.latestProjectData(in: bundle))
    }

    func testIgnoresAlternativeDirectoryWithoutProjectData() throws {
        let bundle = try ProjectDataFixture.makeBundle(
            named: "partial", in: root, alternatives: ["000": Data([1])])
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Alternatives/001", isDirectory: true),
            withIntermediateDirectories: true)
        XCTAssertEqual(locator.latestProjectData(in: bundle)?.alternative, "000")
    }

    /// Un dossier nommé `ProjectData` n'est pas un fichier : il doit être ignoré.
    func testIgnoresDirectoryNamedProjectData() throws {
        let bundle = try ProjectDataFixture.makeBundle(named: "weird", in: root)
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Alternatives/000/ProjectData", isDirectory: true),
            withIntermediateDirectories: true)
        XCTAssertNil(locator.latestProjectData(in: bundle))
    }
}
