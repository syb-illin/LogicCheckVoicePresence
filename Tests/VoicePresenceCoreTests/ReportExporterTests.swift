import XCTest
@testable import VoicePresenceCore

final class ReportExporterTests: XCTestCase {

    private func inspection(_ name: String,
                            _ verdict: Verdict,
                            ambiguous: Int = 0,
                            audioFiles: Int = 0) -> ProjectInspection {
        let linked = [LinkedChannel(slot: 0x14, name: "voice verse 1",
                                    regionCount: verdict == .busWithAudio ? 2 : 0,
                                    isIntermediateBus: false)]
        let analysis = VoiceBusAnalysis(
            matchedBuses: verdict == .noBus
                ? []
                : [MixerChannel(slot: 0x10, name: "Voice bus", outputSlot: 0)],
            linkedChannels: verdict == .noBus ? [] : linked,
            totalNamedChannels: 12,
            totalRegions: 4,
            ambiguousRegions: ambiguous)
        return ProjectInspection(name: name,
                                 url: URL(fileURLWithPath: "/tmp/\(name).logicx"),
                                 alternative: "000",
                                 baseVerdict: verdict,
                                 analysis: analysis,
                                 audioFileCount: audioFiles)
    }

    private func rows(_ csv: String) -> [String] {
        Array(csv.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).dropFirst())
    }

    func testHeaderMatchesColumnDefinition() {
        let csv = ReportExporter.csv([inspection("a", .busWithAudio)])
        XCTAssertEqual(csv.split(separator: "\n").first.map(String.init),
                       ReportExporter.columns.joined(separator: ReportExporter.separator))
    }

    func testEmptyInputStillProducesHeader() {
        XCTAssertEqual(ReportExporter.csv([]).split(separator: "\n").count, 1)
    }

    func testRowCountMatchesInput() {
        let csv = ReportExporter.csv([inspection("a", .busWithAudio),
                                      inspection("b", .busNoAudio),
                                      inspection("c", .noBus)])
        XCTAssertEqual(rows(csv).count, 3)
    }

    func testEveryRowHasExactlyOneFieldPerColumn() {
        let csv = ReportExporter.csv([inspection("a;b", .busWithAudio, ambiguous: 2, audioFiles: 3)])
        let fields = rows(csv)[0].components(separatedBy: ReportExporter.separator)
        XCTAssertEqual(fields.count, ReportExporter.columns.count)
    }

    /// Les cas à traiter d'abord doivent arriver en tête du fichier.
    func testRowsSortedByVerdictRankThenName() {
        let csv = ReportExporter.csv([inspection("zzz", .busWithAudio),
                                      inspection("aaa", .noBus),
                                      inspection("mmm", .undecidable),
                                      inspection("bbb", .busNoAudio)])
        let names = rows(csv).map { $0.components(separatedBy: ReportExporter.separator)[0] }
        XCTAssertEqual(names, ["mmm", "bbb", "zzz", "aaa"])
    }

    func testSameVerdictSortedByNameCaseInsensitively() {
        let csv = ReportExporter.csv([inspection("Zebra", .busWithAudio),
                                      inspection("alpha", .busWithAudio)])
        let names = rows(csv).map { $0.components(separatedBy: ReportExporter.separator)[0] }
        XCTAssertEqual(names, ["alpha", "Zebra"])
    }

    /// Un nom contenant le séparateur ne doit pas décaler les colonnes.
    func testSeparatorInFieldIsNeutralised() {
        XCTAssertEqual(ReportExporter.escape("a;b;c"), "a,b,c")
    }

    func testNewlinesInFieldAreNeutralised() {
        XCTAssertEqual(ReportExporter.escape("a\nb"), "a b")
        XCTAssertEqual(ReportExporter.escape("a\r\nb"), "a b")
        XCTAssertEqual(ReportExporter.escape("a\rb"), "a b")
    }

    func testEscapeLeavesOrdinaryTextIntact() {
        XCTAssertEqual(ReportExporter.escape("voice verse 1"), "voice verse 1")
    }

    func testRationaleIsIncluded() {
        let csv = ReportExporter.csv([inspection("a", .undecidable)])
        XCTAssertTrue(csv.contains(ReportExporter.escape(Verdict.undecidable.rationale)))
    }

    func testAudioNoteIsEmptyWhenAnalysisDidNotRun() {
        let csv = ReportExporter.csv([inspection("a", .busNoAudio)])
        let fields = rows(csv)[0].components(separatedBy: ReportExporter.separator)
        XCTAssertEqual(fields[9], "")
    }

    func testAudioNoteIsIncludedWhenAnalysisRan() {
        var item = inspection("a", .undecidable, audioFiles: 2)
        item.audioAnalysis = AudioAnalysisReport(files: [.stub(vocalConfidence: 0.8)])
        let fields = rows(ReportExporter.csv([item]))[0]
            .components(separatedBy: ReportExporter.separator)
        XCTAssertTrue(fields[9].contains("voix détectée"))
    }

    // MARK: - Résumé

    func testSummaryCountsByVerdictSortedByRank() {
        let summary = ReportExporter.summary([inspection("a", .busWithAudio),
                                              inspection("b", .busWithAudio),
                                              inspection("c", .undecidable)])
        XCTAssertEqual(summary.map(\.verdict), [.undecidable, .busWithAudio])
        XCTAssertEqual(summary.map(\.count), [1, 2])
    }

    func testSummaryOfEmptyInput() {
        XCTAssertTrue(ReportExporter.summary([]).isEmpty)
    }

    func testSummaryUsesEffectiveVerdict() {
        var item = inspection("a", .undecidable, audioFiles: 1)
        item.audioAnalysis = AudioAnalysisReport(files: [.stub(isSilent: true)])
        XCTAssertEqual(ReportExporter.summary([item]).map(\.verdict), [.busNoAudio])
    }

    func testVerdictCountIsIdentifiedByItsVerdict() {
        XCTAssertEqual(VerdictCount(verdict: .busOrphan, count: 3).id, .busOrphan)
    }
}

final class AppInfoTests: XCTestCase {

    func testIdentityConstantsAreCoherent() {
        XCTAssertFalse(AppInfo.name.isEmpty)
        XCTAssertFalse(AppInfo.author.isEmpty)
        XCTAssertEqual(AppInfo.repositoryURL.absoluteString,
                       "https://github.com/\(AppInfo.repositoryOwner)/\(AppInfo.repositoryName)")
        XCTAssertTrue(AppInfo.releasesURL.absoluteString.hasSuffix("/releases"))
        XCTAssertTrue(AppInfo.issuesURL.absoluteString.hasSuffix("/issues"))
        XCTAssertTrue(AppInfo.authorURL.absoluteString.hasSuffix(AppInfo.authorHandle))
    }

    func testBundleIdentifierMatchesLogSubsystem() {
        // Les journaux doivent être filtrables par l'identifiant du bundle.
        XCTAssertEqual(AppInfo.bundleIdentifier, Log.subsystem)
    }

    /// Hors bundle applicatif — c'est le cas sous test — le repli s'applique.
    func testVersionFallsBackOutsideAppBundle() {
        XCTAssertNotNil(SemanticVersion(AppInfo.version))
    }

    func testVersionDisplayIncludesVersionAndBuild() {
        XCTAssertTrue(AppInfo.versionDisplay.contains(AppInfo.version))
        XCTAssertTrue(AppInfo.versionDisplay.contains(AppInfo.build))
    }

    func testCopyrightMentionsAuthor() {
        XCTAssertTrue(AppInfo.copyright.contains(AppInfo.author))
    }
}
