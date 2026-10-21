import XCTest
@testable import VoicePresenceCore

final class RegionStemTests: XCTestCase {

    func testStripsTakeNumber() {
        XCTAssertEqual(RegionAttribution.stem(of: "voice verse 1#05"), "voice verse 1")
    }

    func testStripsCopySuffix() {
        XCTAssertEqual(RegionAttribution.stem(of: "voice chorus.12"), "voice chorus")
    }

    func testStripsChainedCopySuffixes() {
        XCTAssertEqual(RegionAttribution.stem(of: "take.1.2.3"), "take")
    }

    func testStripsTakeThenCopy() {
        XCTAssertEqual(RegionAttribution.stem(of: "voice verse 1#05.1"), "voice verse 1")
        XCTAssertEqual(RegionAttribution.stem(of: "Voice#07.01"), "voice")
    }

    func testTrimsAndLowercases() {
        XCTAssertEqual(RegionAttribution.stem(of: "  Voice Bus  "), "voice bus")
    }

    func testLeavesPlainNameIntact() {
        XCTAssertEqual(RegionAttribution.stem(of: "gratte chorus"), "gratte chorus")
    }

    /// Un suffixe non numérique n'est pas un suffixe de Logic.
    func testDoesNotStripNonNumericSuffix() {
        XCTAssertEqual(RegionAttribution.stem(of: "mix.final"), "mix.final")
        XCTAssertEqual(RegionAttribution.stem(of: "take#final"), "take#final")
    }

    func testDoesNotStripBareSeparator() {
        XCTAssertEqual(RegionAttribution.stem(of: "a."), "a.")
        XCTAssertEqual(RegionAttribution.stem(of: "a#"), "a#")
    }

    func testHandlesEmptyInput() {
        XCTAssertEqual(RegionAttribution.stem(of: ""), "")
        XCTAssertEqual(RegionAttribution.stem(of: "   "), "")
    }

    func testNumericOnlyNameIsNotEmptied() {
        // "42" n'a pas de séparateur : rien à retirer.
        XCTAssertEqual(RegionAttribution.stem(of: "42"), "42")
    }
}

final class RegionScoringTests: XCTestCase {

    func testExactMatchOutranksAnyPrefix() {
        let exact = RegionAttribution.score(stem: "voice", channelName: "voice")
        let prefix = RegionAttribution.score(stem: "voice",
                                             channelName: "voice chorus extended long name")
        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThanOrEqual(exact, RegionAttribution.exactMatchScore)
    }

    func testPrefixInEitherDirectionScores() {
        // Le nom du canal prolonge celui de la région (piste renommée après coup).
        XCTAssertGreaterThan(RegionAttribution.score(stem: "voice",
                                                     channelName: "voice chorus b r"), 0)
        // Et l'inverse.
        XCTAssertGreaterThan(RegionAttribution.score(stem: "voice chorus b r",
                                                     channelName: "voice"), 0)
    }

    func testUnrelatedNamesScoreZero() {
        XCTAssertEqual(RegionAttribution.score(stem: "kick", channelName: "voice"), 0)
        // Préfixe commun partiel sans que l'un prolonge l'autre : pas un match.
        XCTAssertEqual(RegionAttribution.score(stem: "voice chorus",
                                               channelName: "voice verse"), 0)
    }

    func testEmptyNamesScoreZero() {
        XCTAssertEqual(RegionAttribution.score(stem: "", channelName: "voice"), 0)
        XCTAssertEqual(RegionAttribution.score(stem: "voice", channelName: ""), 0)
    }

    func testLongerCommonPrefixScoresHigher() {
        let short = RegionAttribution.score(stem: "vo", channelName: "voice chorus")
        let long = RegionAttribution.score(stem: "voice ch", channelName: "voice chorus")
        XCTAssertGreaterThan(long, short)
    }

    func testCommonPrefixLength() {
        XCTAssertEqual(RegionAttribution.commonPrefixLength("voice", "voice"), 5)
        XCTAssertEqual(RegionAttribution.commonPrefixLength("voice chorus", "voice verse"), 6)
        XCTAssertEqual(RegionAttribution.commonPrefixLength("abc", ""), 0)
        XCTAssertEqual(RegionAttribution.commonPrefixLength("", "abc"), 0)
        XCTAssertEqual(RegionAttribution.commonPrefixLength("abc", "xyz"), 0)
    }
}

final class RegionAttributionTests: XCTestCase {

    private func channels(_ specs: [(Int, String)]) -> [Int: MixerChannel] {
        var result: [Int: MixerChannel] = [:]
        for (slot, name) in specs {
            result[slot] = MixerChannel(slot: slot, name: name, outputSlot: 0)
        }
        return result
    }

    func testAttributesExactMatchToLinkedChannel() {
        let result = RegionAttribution.attribute(
            regionNames: ["voice verse 1", "voice verse 1#02", "voice verse 1#02.3"],
            channels: channels([(0x14, "voice verse 1")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.firmCount(for: 0x14), 3)
        XCTAssertEqual(result.ambiguousCount, 0)
        XCTAssertEqual(result.totalFirm, 3)
    }

    /// Logic fige le nom de région à l'enregistrement : après renommage de la
    /// piste, le nom du canal prolonge celui de la région.
    func testMatchesRegionWhoseChannelWasRenamedLater() {
        let result = RegionAttribution.attribute(
            regionNames: ["Voice chorus", "Voice chorus.1"],
            channels: channels([(0x14, "Voice chorus b R")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.firmCount(for: 0x14), 2)
    }

    func testTiedCandidatesCountAsAmbiguousOnce() {
        let result = RegionAttribution.attribute(
            regionNames: ["Voice chorus", "Voice chorus.1"],
            channels: channels([(0x14, "Voice chorus a"), (0x18, "Voice chorus b")]),
            linkedSlots: [0x14, 0x18])
        XCTAssertEqual(result.ambiguousCount, 2)
        XCTAssertEqual(result.totalFirm, 0)
    }

    func testAmbiguityIsIgnoredWhenNoTiedCandidateIsLinked() {
        let result = RegionAttribution.attribute(
            regionNames: ["drum loop"],
            channels: channels([(0x20, "drum loop a"), (0x24, "drum loop b"), (0x14, "voice")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.ambiguousCount, 0)
        XCTAssertEqual(result.totalFirm, 0)
    }

    /// La concurrence des canaux non liés est ce qui évite les faux positifs.
    func testRegionBelongingToUnlinkedChannelIsNotCounted() {
        let result = RegionAttribution.attribute(
            regionNames: ["kick", "kick#02"],
            channels: channels([(0x14, "voice verse 1"), (0x24, "kick")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.totalFirm, 0)
        XCTAssertEqual(result.ambiguousCount, 0)
    }

    func testExactMatchBeatsPrefixCandidate() {
        let result = RegionAttribution.attribute(
            regionNames: ["voice"],
            channels: channels([(0x14, "voice"), (0x18, "voice chorus extended")]),
            linkedSlots: [0x14, 0x18])
        XCTAssertEqual(result.firmCount(for: 0x14), 1)
        XCTAssertEqual(result.firmCount(for: 0x18), 0)
        XCTAssertEqual(result.ambiguousCount, 0)
    }

    func testRegionMatchingNothingIsIgnored() {
        let result = RegionAttribution.attribute(
            regionNames: ["totally unrelated"],
            channels: channels([(0x14, "voice verse 1")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.totalFirm, 0)
        XCTAssertEqual(result.ambiguousCount, 0)
    }

    func testBlankRegionNameIsIgnored() {
        let result = RegionAttribution.attribute(
            regionNames: ["   ", ""],
            channels: channels([(0x14, "voice verse 1")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.totalFirm, 0)
    }

    func testChannelWithBlankNameIsExcluded() {
        let result = RegionAttribution.attribute(
            regionNames: ["x"],
            channels: channels([(0x14, "   ")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.totalFirm, 0)
    }

    func testEmptyInputsReturnNone() {
        XCTAssertEqual(RegionAttribution.attribute(regionNames: [],
                                                   channels: channels([(1, "a")]),
                                                   linkedSlots: [1]).totalFirm, 0)
        XCTAssertEqual(RegionAttribution.attribute(regionNames: ["a"],
                                                   channels: channels([(1, "a")]),
                                                   linkedSlots: []).totalFirm, 0)
        XCTAssertEqual(RegionAttribution.attribute(regionNames: ["a"],
                                                   channels: [:],
                                                   linkedSlots: [1]).totalFirm, 0)
    }

    func testNoneConstant() {
        XCTAssertEqual(RegionAttribution.none.totalFirm, 0)
        XCTAssertEqual(RegionAttribution.none.ambiguousCount, 0)
        XCTAssertEqual(RegionAttribution.none.firmCount(for: 42), 0)
    }

    /// Le cache par radical ne doit pas changer le résultat, seulement le coût.
    func testRepeatedRegionNamesAreCountedIndividually() {
        let names = Array(repeating: "voice verse 1", count: 50)
        let result = RegionAttribution.attribute(
            regionNames: names,
            channels: channels([(0x14, "voice verse 1")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.firmCount(for: 0x14), 50)
    }

    func testCacheDoesNotLeakAcrossDifferentStems() {
        let result = RegionAttribution.attribute(
            regionNames: ["voice verse 1", "kick", "voice verse 1#02", "kick#01"],
            channels: channels([(0x14, "voice verse 1"), (0x24, "kick")]),
            linkedSlots: [0x14])
        XCTAssertEqual(result.firmCount(for: 0x14), 2)
        XCTAssertEqual(result.firmCount(for: 0x24), 0)
    }
}
