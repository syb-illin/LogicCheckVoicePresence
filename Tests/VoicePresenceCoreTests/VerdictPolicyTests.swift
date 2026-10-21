import XCTest
@testable import VoicePresenceCore

final class VerdictPolicyTests: XCTestCase {

    private func analysis(buses: [Int] = [],
                          linked: [LinkedChannel] = [],
                          regions: Int = 0,
                          ambiguous: Int = 0) -> VoiceBusAnalysis {
        VoiceBusAnalysis(
            matchedBuses: buses.map { MixerChannel(slot: $0, name: "bus \($0)", outputSlot: 0) },
            linkedChannels: linked,
            totalNamedChannels: 10,
            totalRegions: regions,
            ambiguousRegions: ambiguous)
    }

    private func channel(regions: Int) -> LinkedChannel {
        LinkedChannel(slot: 1, name: "piste", regionCount: regions, isIntermediateBus: false)
    }

    // MARK: - Étages 1 et 2

    func testNoBus() {
        XCTAssertEqual(VerdictPolicy.verdict(for: analysis(), audioFileCount: 5), .noBus)
    }

    func testOrphanBus() {
        XCTAssertEqual(VerdictPolicy.verdict(for: analysis(buses: [1]), audioFileCount: 5),
                       .busOrphan)
    }

    func testBusWithAudioWhenAnyChannelHasFirmRegion() {
        let a = analysis(buses: [1], linked: [channel(regions: 0), channel(regions: 3)], regions: 3)
        XCTAssertEqual(VerdictPolicy.verdict(for: a, audioFileCount: 0), .busWithAudio)
    }

    func testProbableWhenOnlyAmbiguous() {
        let a = analysis(buses: [1], linked: [channel(regions: 0)], regions: 9, ambiguous: 9)
        XCTAssertEqual(VerdictPolicy.verdict(for: a, audioFileCount: 2), .busProbableAudio)
    }

    /// Le seul cas où décoder l'audio apporte quelque chose.
    func testUndecidableWhenRegionsAndFilesExistButNothingMatches() {
        let a = analysis(buses: [1], linked: [channel(regions: 0)], regions: 86)
        XCTAssertEqual(VerdictPolicy.verdict(for: a, audioFileCount: 7), .undecidable)
    }

    func testNoAudioWhenProjectHasNoRegions() {
        let a = analysis(buses: [1], linked: [channel(regions: 0)], regions: 0)
        XCTAssertEqual(VerdictPolicy.verdict(for: a, audioFileCount: 0), .busNoAudio)
    }

    func testNoAudioWhenRegionsExistButNoFileOnDisk() {
        let a = analysis(buses: [1], linked: [channel(regions: 0)], regions: 40)
        XCTAssertEqual(VerdictPolicy.verdict(for: a, audioFileCount: 0), .busNoAudio)
    }

    func testNoAudioWhenFilesExistButProjectHasNoRegions() {
        let a = analysis(buses: [1], linked: [channel(regions: 0)], regions: 0)
        XCTAssertEqual(VerdictPolicy.verdict(for: a, audioFileCount: 12), .busNoAudio)
    }

    // MARK: - Révision par l'étage 3

    func testRevisionOnlyAppliesToUndecidable() {
        let vocalReport = AudioAnalysisReport(files: [.stub(vocalConfidence: 0.9)])
        for verdict in Verdict.allCases where verdict != .undecidable {
            XCTAssertEqual(VerdictPolicy.revised(verdict, with: vocalReport), verdict,
                           "\(verdict) ne doit pas être révisé")
        }
    }

    func testVocalDetectedYieldsProbableNotCertain() {
        // La voix prouve qu'il y a du chant dans le projet, pas qu'il passe par
        // le bus : le verdict reste « probable ».
        let report = AudioAnalysisReport(files: [.stub(vocalConfidence: 0.95)])
        XCTAssertEqual(VerdictPolicy.revised(.undecidable, with: report), .busProbableAudio)
    }

    func testNoFileYieldsCertainNoAudio() {
        XCTAssertEqual(VerdictPolicy.revised(.undecidable, with: .empty), .busNoAudio)
    }

    /// Le silence est une preuve : aucun audio dans le projet, donc aucun sur le bus.
    func testAllSilentYieldsNoAudio() {
        let report = AudioAnalysisReport(files: [.stub(isSilent: true), .stub(isSilent: true)])
        XCTAssertEqual(VerdictPolicy.revised(.undecidable, with: report), .busNoAudio)
    }

    func testSignalWithoutVocalStaysUndecidable() {
        let report = AudioAnalysisReport(files: [.stub(vocalConfidence: 0.1)])
        XCTAssertEqual(VerdictPolicy.revised(.undecidable, with: report), .undecidable)
    }

    func testVocalBelowThresholdIsNotVocal() {
        let below = AudioAnalysisPolicy.vocalConfidenceThreshold - 0.01
        let report = AudioAnalysisReport(files: [.stub(vocalConfidence: below)])
        XCTAssertEqual(VerdictPolicy.revised(.undecidable, with: report), .undecidable)
    }

    func testVocalAtThresholdCounts() {
        let report = AudioAnalysisReport(files: [
            .stub(vocalConfidence: AudioAnalysisPolicy.vocalConfidenceThreshold)
        ])
        XCTAssertEqual(VerdictPolicy.revised(.undecidable, with: report), .busProbableAudio)
    }

    /// Un fichier en échec ne compte pas comme du signal : on ne conclut pas
    /// « sans audio » sur la foi d'une mesure ratée.
    func testFailedMeasurementIsNotSignal() {
        let report = AudioAnalysisReport(files: [.stub(failure: "illisible")])
        XCTAssertEqual(VerdictPolicy.revised(.undecidable, with: report), .busNoAudio)
        XCTAssertFalse(report.containsSignal)
    }

    // MARK: - Métadonnées du verdict

    func testOnlyUndecidableBenefitsFromAudioAnalysis() {
        for verdict in Verdict.allCases {
            XCTAssertEqual(verdict.benefitsFromAudioAnalysis, verdict == .undecidable, "\(verdict)")
        }
    }

    func testSortRanksArePairwiseDistinct() {
        let ranks = Verdict.allCases.map(\.sortRank)
        XCTAssertEqual(Set(ranks).count, ranks.count)
    }

    func testUndecidableSortsFirst() {
        XCTAssertEqual(Verdict.allCases.min { $0.sortRank < $1.sortRank }, .undecidable)
    }

    func testEveryVerdictHasRationaleAndLabel() {
        for verdict in Verdict.allCases {
            XCTAssertFalse(verdict.rawValue.isEmpty, "\(verdict)")
            XCTAssertFalse(verdict.rationale.isEmpty, "\(verdict)")
        }
    }
}

final class AudioAnalysisPolicyTests: XCTestCase {

    func testRecognisesVocalLabels() {
        for label in ["speech", "Speech", "singing", "male_singing", "choir_singing",
                      "humming", "rapping", "whispering", "yodeling", "vocal_music"] {
            XCTAssertTrue(AudioAnalysisPolicy.isVocalLabel(label), label)
        }
    }

    func testRejectsNonVocalLabels() {
        for label in ["drum", "guitar", "piano", "silence", "music", "bass_guitar"] {
            XCTAssertFalse(AudioAnalysisPolicy.isVocalLabel(label), label)
        }
    }

    func testVocalConfidenceTakesMaximumAcrossVocalLabels() {
        let scores = ["speech": 0.3, "singing": 0.82, "guitar": 0.99]
        XCTAssertEqual(AudioAnalysisPolicy.vocalConfidence(from: scores), 0.82, accuracy: 0.0001)
    }

    func testVocalConfidenceIsZeroWithoutVocalLabel() {
        XCTAssertEqual(AudioAnalysisPolicy.vocalConfidence(from: ["drum": 0.9]), 0)
        XCTAssertEqual(AudioAnalysisPolicy.vocalConfidence(from: [:]), 0)
    }

    func testSilenceThreshold() {
        XCTAssertTrue(AudioAnalysisPolicy.isSilent(peakDB: -.infinity))
        XCTAssertTrue(AudioAnalysisPolicy.isSilent(peakDB: -90))
        XCTAssertFalse(AudioAnalysisPolicy.isSilent(peakDB: AudioAnalysisPolicy.silenceThresholdDB))
        XCTAssertFalse(AudioAnalysisPolicy.isSilent(peakDB: -6))
        XCTAssertFalse(AudioAnalysisPolicy.isSilent(peakDB: 0))
    }

    func testAudioFileRecognitionIsCaseInsensitive() {
        XCTAssertTrue(AudioAnalysisPolicy.isAudioFile(URL(fileURLWithPath: "/a/b.WAV")))
        XCTAssertTrue(AudioAnalysisPolicy.isAudioFile(URL(fileURLWithPath: "/a/b.aiff")))
        XCTAssertTrue(AudioAnalysisPolicy.isAudioFile(URL(fileURLWithPath: "/a/b.caf")))
        XCTAssertFalse(AudioAnalysisPolicy.isAudioFile(URL(fileURLWithPath: "/a/b.txt")))
        XCTAssertFalse(AudioAnalysisPolicy.isAudioFile(URL(fileURLWithPath: "/a/b")))
    }
}

final class AudioAnalysisReportTests: XCTestCase {

    func testEmptyReport() {
        XCTAssertFalse(AudioAnalysisReport.empty.containsVocal)
        XCTAssertFalse(AudioAnalysisReport.empty.containsSignal)
        XCTAssertEqual(AudioAnalysisReport.empty.maxVocalConfidence, 0)
        XCTAssertEqual(AudioAnalysisReport.empty.note, "aucun fichier audio")
    }

    func testNoteReflectsAggregateState() {
        XCTAssertEqual(AudioAnalysisReport(files: [.stub(isSilent: true)]).note,
                       "tous les fichiers sont silencieux")
        XCTAssertEqual(AudioAnalysisReport(files: [.stub(vocalConfidence: 0.1)]).note,
                       "signal présent, pas de voix détectée")
        XCTAssertTrue(AudioAnalysisReport(files: [.stub(vocalConfidence: 0.77)]).note
            .contains("voix détectée"))
    }

    func testMaxVocalConfidenceAcrossFiles() {
        let report = AudioAnalysisReport(files: [.stub(fileName: "a", vocalConfidence: 0.2),
                                                .stub(fileName: "b", vocalConfidence: 0.61)])
        XCTAssertEqual(report.maxVocalConfidence, 0.61, accuracy: 0.0001)
        XCTAssertTrue(report.containsVocal)
    }

    func testMeasurementSummaryBranches() {
        XCTAssertEqual(AudioFileMeasurement.stub(failure: "boom").summary, "erreur : boom")
        XCTAssertEqual(AudioFileMeasurement.stub(isSilent: true).summary, "silencieux")
        XCTAssertEqual(AudioFileMeasurement.stub(vocalConfidence: 0).summary,
                       "pas de voix détectée")
        XCTAssertTrue(AudioFileMeasurement.stub(vocalConfidence: 0.5).summary.contains("voix"))
    }
}
