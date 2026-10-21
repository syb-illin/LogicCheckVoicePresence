import XCTest
@testable import VoicePresenceCore

/// Le lecteur est la seule porte d'entrée vers des octets non fiables : tout ce
/// qui suit en dépend, donc ses cas limites sont testés exhaustivement.
final class ByteReaderTests: XCTestCase {

    private func reader(_ bytes: [UInt8]) -> ByteReader { ByteReader(Data(bytes)) }

    // MARK: - byte

    func testByteReadsInBounds() {
        let r = reader([0x10, 0x20, 0x30])
        XCTAssertEqual(r.byte(at: 0), 0x10)
        XCTAssertEqual(r.byte(at: 2), 0x30)
    }

    func testByteRejectsOutOfBounds() {
        let r = reader([0x10])
        XCTAssertNil(r.byte(at: 1))
        XCTAssertNil(r.byte(at: -1))
        XCTAssertNil(reader([]).byte(at: 0))
    }

    // MARK: - u16

    func testU16IsLittleEndian() {
        XCTAssertEqual(reader([0x34, 0x12]).u16(at: 0), 0x1234)
        XCTAssertEqual(reader([0x00, 0x01]).u16(at: 0), 0x0100)
        XCTAssertEqual(reader([0xFF, 0xFF]).u16(at: 0), 0xFFFF)
    }

    func testU16RejectsTruncatedAndNegativeOffsets() {
        let r = reader([0x01, 0x02, 0x03])
        XCTAssertEqual(r.u16(at: 1), 0x0302)
        XCTAssertNil(r.u16(at: 2))      // un seul octet restant
        XCTAssertNil(r.u16(at: 3))
        XCTAssertNil(r.u16(at: -1))
    }

    // MARK: - contains

    func testContainsAcceptsExactFit() {
        let r = reader([1, 2, 3, 4])
        XCTAssertTrue(r.contains(offset: 0, length: 4))
        XCTAssertTrue(r.contains(offset: 3, length: 1))
        XCTAssertTrue(r.contains(offset: 4, length: 0))
    }

    func testContainsRejectsOverrunAndNegatives() {
        let r = reader([1, 2, 3, 4])
        XCTAssertFalse(r.contains(offset: 1, length: 4))
        XCTAssertFalse(r.contains(offset: -1, length: 1))
        XCTAssertFalse(r.contains(offset: 0, length: -1))
    }

    // MARK: - lengthPrefixedASCII

    func testReadsLengthPrefixedASCII() {
        var bytes: [UInt8] = [0x05, 0x00]
        bytes += Array("Voice".utf8)
        XCTAssertEqual(reader(bytes).lengthPrefixedASCII(at: 0, maxLength: 64), "Voice")
    }

    func testReadsNameAtNonZeroOffset() {
        var bytes: [UInt8] = [0xFF, 0xFF, 0xFF]
        bytes += [0x03, 0x00]
        bytes += Array("bus".utf8)
        XCTAssertEqual(reader(bytes).lengthPrefixedASCII(at: 3, maxLength: 64), "bus")
    }

    func testRejectsZeroLength() {
        XCTAssertNil(reader([0x00, 0x00, 0x41]).lengthPrefixedASCII(at: 0, maxLength: 64))
    }

    func testRejectsLengthAtOrAboveMaximum() {
        var bytes: [UInt8] = [0x40, 0x00]            // 64
        bytes += Array(repeating: 0x41, count: 64)
        XCTAssertNil(reader(bytes).lengthPrefixedASCII(at: 0, maxLength: 64))
        // Une longueur juste en dessous passe.
        var ok: [UInt8] = [0x3F, 0x00]               // 63
        ok += Array(repeating: 0x41, count: 63)
        XCTAssertEqual(reader(ok).lengthPrefixedASCII(at: 0, maxLength: 64)?.count, 63)
    }

    func testRejectsTruncatedPayload() {
        XCTAssertNil(reader([0x08, 0x00, 0x41, 0x42]).lengthPrefixedASCII(at: 0, maxLength: 64))
    }

    /// Ce filtre est ce qui distingue un vrai nom d'une coïncidence binaire.
    func testRejectsNonPrintableBytes() {
        XCTAssertNil(reader([0x03, 0x00, 0x41, 0x00, 0x42]).lengthPrefixedASCII(at: 0, maxLength: 64))
        XCTAssertNil(reader([0x02, 0x00, 0x41, 0xFF]).lengthPrefixedASCII(at: 0, maxLength: 64))
        XCTAssertNil(reader([0x02, 0x00, 0x41, 0x1F]).lengthPrefixedASCII(at: 0, maxLength: 64))
        XCTAssertNil(reader([0x02, 0x00, 0x41, 0x7F]).lengthPrefixedASCII(at: 0, maxLength: 64))
    }

    func testAcceptsSpaceAndPrintableBoundaries() {
        // L'espace (0x20) et le tilde (0x7E) sont les bornes valides.
        let bytes: [UInt8] = [0x02, 0x00, 0x20, 0x7E]
        XCTAssertEqual(reader(bytes).lengthPrefixedASCII(at: 0, maxLength: 64), " ~")
    }

    func testRejectsNegativeOffset() {
        XCTAssertNil(reader([0x01, 0x00, 0x41]).lengthPrefixedASCII(at: -2, maxLength: 64))
    }

    // MARK: - offsets(of:)

    func testFindsAllOccurrences() {
        let r = ByteReader(Data("xxABxxABxx".utf8))
        XCTAssertEqual(r.offsets(of: Data("AB".utf8)), [2, 6])
    }

    func testFindsOverlappingOccurrences() {
        // La recherche avance d'un octet : les recouvrements sont trouvés.
        let r = ByteReader(Data("AAAA".utf8))
        XCTAssertEqual(r.offsets(of: Data("AA".utf8)), [0, 1, 2])
    }

    func testRejectsFalseStart() {
        let r = ByteReader(Data("AAB".utf8))
        XCTAssertEqual(r.offsets(of: Data("AB".utf8)), [1])
    }

    func testReturnsEmptyForAbsentOrOversizedPattern() {
        let r = ByteReader(Data("abc".utf8))
        XCTAssertTrue(r.offsets(of: Data("zz".utf8)).isEmpty)
        XCTAssertTrue(r.offsets(of: Data("abcd".utf8)).isEmpty)
        XCTAssertTrue(r.offsets(of: Data()).isEmpty)
        XCTAssertTrue(ByteReader(Data()).offsets(of: Data("a".utf8)).isEmpty)
    }

    func testFindsPatternAtVeryEnd() {
        let r = ByteReader(Data("xxxAB".utf8))
        XCTAssertEqual(r.offsets(of: Data("AB".utf8)), [3])
    }

    // MARK: - Tranches

    /// `Data` issu d'une tranche ne commence pas à l'index 0 : les offsets
    /// doivent rester relatifs au début de la tranche, pas du tampon d'origine.
    func testOffsetsAreRelativeToSliceStart() {
        let full = Data("ZZZZ\u{0}ABCD".utf8)
        let slice = full.dropFirst(5)
        let r = ByteReader(slice)
        XCTAssertEqual(r.count, 4)
        XCTAssertEqual(r.byte(at: 0), UInt8(ascii: "A"))
        XCTAssertEqual(r.offsets(of: Data("CD".utf8)), [2])
    }

    func testLengthPrefixedASCIIOnSlice() {
        var bytes: [UInt8] = Array(repeating: 0x00, count: 7)
        bytes += [0x03, 0x00]
        bytes += Array("bus".utf8)
        let slice = Data(bytes).dropFirst(7)
        XCTAssertEqual(ByteReader(slice).lengthPrefixedASCII(at: 0, maxLength: 64), "bus")
    }
}
