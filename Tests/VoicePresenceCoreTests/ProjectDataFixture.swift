import Foundation
@testable import VoicePresenceCore

/// Fabrique des binaires `ProjectData` synthétiques reproduisant la disposition
/// réelle des chunks, et des bundles `.logicx` sur disque.
///
/// Les offsets sont lus dans ``LogicFormat`` et non recopiés : si une
/// recalibration les déplace, les fixtures suivent et les tests restent valides.
/// Aucun projet réel n'est embarqué dans le dépôt.
enum ProjectDataFixture {

    /// Taille des chunks produits. Supérieure au minimum exigé par le parseur,
    /// pour que des noms longs tiennent après leur offset.
    static let channelChunkSize = 0x160
    static let regionChunkSize = 0x120

    struct ChannelSpec {
        let slot: Int
        let name: String
        let output: Int

        init(slot: Int, name: String, output: Int = LogicFormat.unassignedSlot) {
            self.slot = slot
            self.name = name
            self.output = output
        }
    }

    // MARK: - Chunks

    static func channelChunk(_ spec: ChannelSpec) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: channelChunkSize)
        write(magic: LogicFormat.channelMagic, into: &bytes)
        writeU16(spec.slot, at: LogicFormat.channelSlotOffset, into: &bytes)
        writeU16(spec.output, at: LogicFormat.channelOutputOffset, into: &bytes)
        writeString(spec.name, at: LogicFormat.channelNameOffset, into: &bytes)
        return bytes
    }

    static func regionChunk(name: String) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: regionChunkSize)
        write(magic: LogicFormat.regionMagic, into: &bytes)
        writeString(name, at: LogicFormat.regionNameOffset, into: &bytes)
        return bytes
    }

    /// Assemble un `ProjectData` complet, avec du remplissage non nul entre les
    /// chunks : un parseur qui dépendrait d'un alignement ou de zéros se ferait
    /// prendre ici.
    static func projectData(channels: [ChannelSpec], regions: [String]) -> Data {
        var bytes: [UInt8] = Array(repeating: 0xAB, count: 48)
        for channel in channels {
            bytes += channelChunk(channel)
            bytes += Array(repeating: 0xCD, count: 24)
        }
        for region in regions {
            bytes += regionChunk(name: region)
            bytes += Array(repeating: 0xEF, count: 24)
        }
        return Data(bytes)
    }

    static func reader(channels: [ChannelSpec], regions: [String]) -> ByteReader {
        ByteReader(projectData(channels: channels, regions: regions))
    }

    // MARK: - Bundles sur disque

    /// Crée un faux bundle `.logicx`.
    ///
    /// Les dates de modification sont assignées dans l'ordre alphabétique des
    /// alternatives, donc de façon déterministe : la dernière est la plus
    /// récente. ``touch(bundle:alternative:date:)`` permet de forcer un autre
    /// ordre dans un test précis.
    @discardableResult
    static func makeBundle(named name: String,
                           in root: URL,
                           alternatives: [String: Data] = [:],
                           audioFileNames: [String] = [],
                           legacyProjectData: Data? = nil) throws -> URL {
        let fileManager = FileManager.default
        let bundle = root.appendingPathComponent("\(name).logicx", isDirectory: true)
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)

        for (index, entry) in alternatives.sorted(by: { $0.key < $1.key }).enumerated() {
            let directory = bundle.appendingPathComponent("Alternatives/\(entry.key)",
                                                          isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("ProjectData")
            try entry.value.write(to: file)
            try fileManager.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1_000_000 + Double(index) * 3600)],
                ofItemAtPath: file.path)
        }

        if let legacyProjectData {
            try legacyProjectData.write(to: bundle.appendingPathComponent("ProjectData"))
        }

        if !audioFileNames.isEmpty {
            let media = bundle.appendingPathComponent("Media/Audio Files", isDirectory: true)
            try fileManager.createDirectory(at: media, withIntermediateDirectories: true)
            for fileName in audioFileNames {
                try Data().write(to: media.appendingPathComponent(fileName))
            }
        }
        return bundle
    }

    /// Ajoute une sauvegarde sous une alternative, pour vérifier qu'elle est
    /// bien ignorée par la sélection.
    static func addBackup(to bundle: URL, alternative: String, data: Data) throws {
        let directory = bundle
            .appendingPathComponent("Alternatives/\(alternative)/Project File Backups/00",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("ProjectData")
        try data.write(to: file)
        // Volontairement plus récente que toutes les alternatives.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 9_000_000)],
            ofItemAtPath: file.path)
    }

    static func touch(bundle: URL, alternative: String, date: Date) throws {
        let file = bundle.appendingPathComponent("Alternatives/\(alternative)/ProjectData")
        try FileManager.default.setAttributes([.modificationDate: date],
                                              ofItemAtPath: file.path)
    }

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoicePresenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Écriture

    private static func write(magic: Data, into bytes: inout [UInt8]) {
        for (index, byte) in magic.enumerated() { bytes[index] = byte }
    }

    private static func writeU16(_ value: Int, at offset: Int, into bytes: inout [UInt8]) {
        bytes[offset] = UInt8(value & 0xFF)
        bytes[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeString(_ string: String, at offset: Int, into bytes: inout [UInt8]) {
        let ascii = Array(string.utf8)
        precondition(offset + 2 + ascii.count <= bytes.count,
                     "Nom trop long pour la taille de chunk de la fixture")
        writeU16(ascii.count, at: offset, into: &bytes)
        for (index, byte) in ascii.enumerated() { bytes[offset + 2 + index] = byte }
    }
}

// MARK: - Doublures

/// Analyseur audio factice : permet de tester l'enchaînement des verdicts sans
/// fabriquer de vrais fichiers audio ni dépendre du classifieur système, qui
/// n'est pas garanti disponible sur un runner de CI.
struct StubAudioAnalyzer: AudioAnalyzing {
    var files: [URL] = []
    var report: AudioAnalysisReport = .empty

    func audioFiles(in project: URL) -> [URL] { files }
    func analyze(project: URL) async -> AudioAnalysisReport { report }
}

extension AudioFileMeasurement {
    /// Mesure synthétique, pour les tests d'agrégation.
    static func stub(fileName: String = "a.wav",
                     duration: TimeInterval = 10,
                     peakDB: Float = -6,
                     isSilent: Bool = false,
                     vocalConfidence: Double = 0,
                     labels: [ClassifiedLabel] = [],
                     failure: String? = nil) -> AudioFileMeasurement {
        AudioFileMeasurement(fileName: fileName, duration: duration, peakDB: peakDB,
                             isSilent: isSilent, labels: labels,
                             vocalConfidence: vocalConfidence, failure: failure)
    }
}

/// Transport factice pour ``UpdateChecker``.
struct StubReleaseFetcher: ReleaseFetching {
    var payload: Data?
    var error: Error?

    func fetchLatestRelease() async throws -> Data {
        if let error { throw error }
        return payload ?? Data()
    }

    /// Réponse GitHub minimale, limitée aux champs réellement décodés.
    static func releasePayload(tag: String,
                              name: String? = nil,
                              body: String = "",
                              assets: [(String, String)] = [("App.zip", "https://example.com/App.zip")])
    -> Data {
        let assetList = assets
            .map { #"{"name":"\#($0.0)","browser_download_url":"\#($0.1)"}"# }
            .joined(separator: ",")
        let nameField = name.map { #""name":"\#($0)","# } ?? ""
        let json = """
        {"tag_name":"\(tag)",\(nameField)"body":"\(body)",
         "html_url":"https://github.com/o/r/releases/tag/\(tag)",
         "published_at":"2026-01-02T03:04:05Z","assets":[\(assetList)]}
        """
        return Data(json.utf8)
    }
}
