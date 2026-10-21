import XCTest
@testable import VoicePresenceCore

final class SemanticVersionTests: XCTestCase {

    // MARK: - Analyse

    func testParsesThreeComponents() throws {
        let version = try XCTUnwrap(SemanticVersion("1.2.3"))
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 3)
        XCTAssertTrue(version.prerelease.isEmpty)
    }

    func testAcceptsLeadingV() {
        XCTAssertEqual(SemanticVersion("v1.2.3"), SemanticVersion("1.2.3"))
        XCTAssertEqual(SemanticVersion("V1.2.3"), SemanticVersion("1.2.3"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(SemanticVersion("  v1.2.3\n"), SemanticVersion("1.2.3"))
    }

    /// Les tags de release n'ont pas toujours trois composants.
    func testCompletesShortForms() {
        XCTAssertEqual(SemanticVersion("1"), SemanticVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(SemanticVersion("1.2"), SemanticVersion(major: 1, minor: 2, patch: 0))
    }

    func testParsesPrerelease() throws {
        let version = try XCTUnwrap(SemanticVersion("1.0.0-beta.2"))
        XCTAssertEqual(version.prerelease, ["beta", "2"])
        XCTAssertTrue(version.isPrerelease)
    }

    func testIgnoresBuildMetadata() {
        XCTAssertEqual(SemanticVersion("1.2.3+abc123"), SemanticVersion("1.2.3"))
        XCTAssertEqual(SemanticVersion("1.2.3-rc.1+abc"), SemanticVersion("1.2.3-rc.1"))
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(SemanticVersion(""))
        XCTAssertNil(SemanticVersion("v"))
        XCTAssertNil(SemanticVersion("abc"))
        XCTAssertNil(SemanticVersion("1.2.3.4"))
        XCTAssertNil(SemanticVersion("1.x.3"))
        XCTAssertNil(SemanticVersion("-1.2.3"))
        XCTAssertNil(SemanticVersion("1..3"))
    }

    // MARK: - Comparaison

    /// Le piège que la comparaison de chaînes ne passe pas.
    func testTenIsGreaterThanNine() {
        XCTAssertGreaterThan(SemanticVersion("1.10.0")!, SemanticVersion("1.9.0")!)
        XCTAssertGreaterThan(SemanticVersion("1.0.10")!, SemanticVersion("1.0.9")!)
        XCTAssertGreaterThan(SemanticVersion("10.0.0")!, SemanticVersion("9.9.9")!)
    }

    func testComparesComponentsInOrder() {
        XCTAssertLessThan(SemanticVersion("1.0.0")!, SemanticVersion("2.0.0")!)
        XCTAssertLessThan(SemanticVersion("1.1.0")!, SemanticVersion("1.2.0")!)
        XCTAssertLessThan(SemanticVersion("1.1.1")!, SemanticVersion("1.1.2")!)
    }

    func testEqualVersionsAreNotLess() {
        let a = SemanticVersion("1.2.3")!
        XCTAssertFalse(a < a)
        XCTAssertEqual(a, SemanticVersion("1.2.3")!)
    }

    /// Semver : une préversion précède la version finale correspondante.
    func testPrereleasePrecedesRelease() {
        XCTAssertLessThan(SemanticVersion("1.0.0-beta")!, SemanticVersion("1.0.0")!)
        XCTAssertGreaterThan(SemanticVersion("1.0.0")!, SemanticVersion("1.0.0-rc.1")!)
    }

    func testPrereleaseOrdering() {
        XCTAssertLessThan(SemanticVersion("1.0.0-alpha")!, SemanticVersion("1.0.0-beta")!)
        XCTAssertLessThan(SemanticVersion("1.0.0-beta.1")!, SemanticVersion("1.0.0-beta.2")!)
        // Numérique avant alphanumérique.
        XCTAssertLessThan(SemanticVersion("1.0.0-1")!, SemanticVersion("1.0.0-alpha")!)
        // Moins d'identifiants = plus petit.
        XCTAssertLessThan(SemanticVersion("1.0.0-beta")!, SemanticVersion("1.0.0-beta.1")!)
    }

    func testPrereleaseNumericComparisonIsNotLexicographic() {
        XCTAssertLessThan(SemanticVersion("1.0.0-beta.9")!, SemanticVersion("1.0.0-beta.10")!)
    }

    func testSortingOrdersAscending() {
        let versions = ["1.0.0", "0.9.9", "1.0.0-beta", "1.10.0", "1.2.0"]
            .compactMap(SemanticVersion.init)
            .sorted()
            .map(\.description)
        XCTAssertEqual(versions, ["0.9.9", "1.0.0-beta", "1.0.0", "1.2.0", "1.10.0"])
    }

    // MARK: - Rendu

    func testDescriptionRoundTrips() {
        for text in ["1.2.3", "0.0.1", "1.0.0-beta.2", "2.10.0-rc.1"] {
            XCTAssertEqual(SemanticVersion(text)?.description, text)
        }
    }

    func testHashableConformance() {
        let set: Set<SemanticVersion> = [SemanticVersion("1.0.0")!, SemanticVersion("v1.0.0")!]
        XCTAssertEqual(set.count, 1)
    }
}
