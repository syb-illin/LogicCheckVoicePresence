import XCTest
@testable import VoicePresenceCore

/// Aucun accès réseau : le transport est remplacé par une doublure, donc ces
/// tests sont déterministes et tournent hors ligne en CI.
final class UpdateCheckerTests: XCTestCase {

    private func checker(payload: Data? = nil,
                         error: Error? = nil,
                         current: String = "1.0.0",
                         includePrereleases: Bool = false) -> UpdateChecker {
        UpdateChecker(fetcher: StubReleaseFetcher(payload: payload, error: error),
                      currentVersion: SemanticVersion(current),
                      includePrereleases: includePrereleases)
    }

    // MARK: - Comparaison

    func testDetectsNewerVersion() async throws {
        let status = await checker(payload: StubReleaseFetcher.releasePayload(tag: "v1.1.0")).check()
        let release = try XCTUnwrap(status.release)
        XCTAssertEqual(release.version.description, "1.1.0")
        XCTAssertEqual(release.tag, "v1.1.0")
    }

    func testReportsUpToDateForSameVersion() async {
        let status = await checker(payload: StubReleaseFetcher.releasePayload(tag: "v1.0.0")).check()
        XCTAssertEqual(status, .upToDate(current: SemanticVersion("1.0.0")!))
    }

    func testReportsUpToDateForOlderPublishedVersion() async {
        let status = await checker(payload: StubReleaseFetcher.releasePayload(tag: "v0.9.0")).check()
        XCTAssertEqual(status, .upToDate(current: SemanticVersion("1.0.0")!))
    }

    func testMinorVersionJumpIsComparedNumerically() async throws {
        let status = await checker(payload: StubReleaseFetcher.releasePayload(tag: "v1.10.0"),
                                   current: "1.9.0").check()
        XCTAssertNotNil(status.release)
    }

    // MARK: - Préversions

    func testPrereleaseIgnoredByDefault() async {
        let status = await checker(payload: StubReleaseFetcher.releasePayload(tag: "v2.0.0-beta.1"))
            .check()
        XCTAssertEqual(status, .upToDate(current: SemanticVersion("1.0.0")!))
    }

    func testPrereleaseOfferedWhenRequested() async {
        let status = await checker(payload: StubReleaseFetcher.releasePayload(tag: "v2.0.0-beta.1"),
                                   includePrereleases: true).check()
        XCTAssertNotNil(status.release)
    }

    // MARK: - Erreurs

    /// Pas de release publiée : ce n'est pas une anomalie, l'app est à jour.
    func testNoReleasesIsTreatedAsUpToDate() async {
        let status = await checker(error: UpdateError.noReleases).check()
        XCTAssertEqual(status, .upToDate(current: SemanticVersion("1.0.0")!))
    }

    /// Un échec est dit comme tel : afficher « à jour » quand la vérification
    /// n'a pas abouti serait trompeur.
    func testRateLimitIsReportedAsFailure() async {
        guard case .failed(let message) = await checker(error: UpdateError.rateLimited).check()
        else { return XCTFail("attendu .failed") }
        XCTAssertTrue(message.contains("Quota"))
    }

    func testUnexpectedResponseIsReportedAsFailure() async {
        let status = await checker(error: UpdateError.unexpectedResponse("HTTP 500")).check()
        guard case .failed(let message) = status else { return XCTFail("attendu .failed") }
        XCTAssertTrue(message.contains("500"))
    }

    func testMalformedPayloadIsReportedAsFailure() async {
        let status = await checker(payload: Data("pas du json".utf8)).check()
        guard case .failed = status else { return XCTFail("attendu .failed") }
    }

    func testPayloadWithUnparsableTagIsReportedAsFailure() async {
        let status = await checker(payload: StubReleaseFetcher.releasePayload(tag: "latest")).check()
        guard case .failed = status else { return XCTFail("attendu .failed") }
    }

    // MARK: - Décodage

    func testDecodesReleaseFields() throws {
        let payload = StubReleaseFetcher.releasePayload(
            tag: "v1.4.0", name: "Version 1.4", body: "Corrige le tri",
            assets: [("notes.txt", "https://example.com/notes.txt"),
                     ("LogicCheckVoicePresence.zip", "https://example.com/app.zip")])
        let release = try UpdateChecker.decodeRelease(from: payload)

        XCTAssertEqual(release.version.description, "1.4.0")
        XCTAssertEqual(release.title, "Version 1.4")
        XCTAssertEqual(release.notes, "Corrige le tri")
        // L'archive est préférée au premier asset venu.
        XCTAssertEqual(release.downloadURL?.lastPathComponent, "app.zip")
        XCTAssertNotNil(release.publishedAt)
    }

    func testFallsBackToFirstAssetWhenNoArchive() throws {
        let payload = StubReleaseFetcher.releasePayload(
            tag: "v1.0.1", assets: [("app.dmg", "https://example.com/app.dmg")])
        XCTAssertEqual(try UpdateChecker.decodeRelease(from: payload).downloadURL?
            .lastPathComponent, "app.dmg")
    }

    func testHandlesReleaseWithoutAssets() throws {
        let payload = StubReleaseFetcher.releasePayload(tag: "v1.0.1", assets: [])
        XCTAssertNil(try UpdateChecker.decodeRelease(from: payload).downloadURL)
    }

    func testTitleFallsBackToTag() throws {
        let payload = StubReleaseFetcher.releasePayload(tag: "v1.0.1", name: nil)
        XCTAssertEqual(try UpdateChecker.decodeRelease(from: payload).title, "v1.0.1")
    }

    func testDecodingRejectsEmptyData() {
        XCTAssertThrowsError(try UpdateChecker.decodeRelease(from: Data())) { error in
            XCTAssertEqual(error as? UpdateError, .malformedPayload)
        }
    }

    func testErrorDescriptionsAreLocalised() {
        for error in [UpdateError.noReleases, .rateLimited, .unexpectedResponse("x"),
                      .malformedPayload] {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error)")
        }
    }
}
