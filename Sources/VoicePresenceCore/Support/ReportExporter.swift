import Foundation

/// Export des résultats en CSV.
///
/// Séparateur point-virgule et décimales à la virgule : c'est ce qu'attend
/// Excel en locale française, où un fichier séparé par des virgules atterrit
/// dans une seule colonne.
public enum ReportExporter {

    public static let separator = ";"

    public static let columns = ["Projet", "Verdict", "Bus", "Canaux liés",
                                 "Canaux avec audio", "Régions fermes", "Régions ambiguës",
                                 "Fichiers audio", "Alternative", "Note audio", "Justification"]

    public static func csv(_ inspections: [ProjectInspection]) -> String {
        let sorted = inspections.sorted {
            ($0.verdict.sortRank, $0.name.localizedLowercase)
                < ($1.verdict.sortRank, $1.name.localizedLowercase)
        }
        var lines = [columns.joined(separator: separator)]
        lines.reserveCapacity(sorted.count + 1)
        for inspection in sorted {
            lines.append([
                inspection.name,
                inspection.verdict.rawValue,
                inspection.busLabel,
                String(inspection.linkedChannelCount),
                String(inspection.channelsWithAudio),
                String(inspection.firmRegions),
                String(inspection.ambiguousRegions),
                String(inspection.audioFileCount),
                inspection.alternative,
                inspection.audioNote ?? "",
                inspection.verdict.rationale,
            ].map(escape).joined(separator: separator))
        }
        return lines.joined(separator: "\n")
    }

    /// Neutralise ce qui casserait la structure du fichier.
    ///
    /// Les séparateurs et retours à la ligne présents dans un nom de projet sont
    /// remplacés, et non échappés par des guillemets : un nom de projet n'a pas
    /// à survivre intact à un export, alors qu'un fichier décalé d'une colonne
    /// est inexploitable.
    static func escape(_ field: String) -> String {
        field
            .replacingOccurrences(of: separator, with: ",")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Résumé par verdict, pour l'affichage et les journaux.
    public static func summary(_ inspections: [ProjectInspection]) -> [(Verdict, Int)] {
        Dictionary(grouping: inspections, by: \.verdict)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0.sortRank < $1.0.sortRank }
    }
}
