import SwiftUI
import AppKit
import VoicePresenceCore

/// Détail d'un projet : la chaîne de routage reconstruite et, si elle a tourné,
/// la mesure audio.
///
/// Le but est que l'utilisateur puisse **contredire** le verdict : il voit les
/// canaux retenus, lesquels sont des bus intermédiaires, combien de régions sont
/// rattachées, et les libellés bruts du classifieur. Rien n'est présenté comme
/// une boîte noire.
struct ProjectDetailView: View {
    let inspection: ProjectInspection
    let analyzeAudio: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            routingSection
            Divider()
            audioSection
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 600)
    }

    // MARK: - En-tête

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(inspection.name).font(.title2.bold())
                Spacer()
                VerdictBadge(verdict: inspection.verdict)
                    .font(.headline)
            }

            Text(inspection.verdict.rationale)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 18) {
                metric("Bus", inspection.busLabel)
                metric("Alternative", inspection.alternative)
                metric("Canaux nommés", "\(inspection.analysis.totalNamedChannels)")
                metric("Régions du projet", "\(inspection.analysis.totalRegions)")
                metric("Fichiers audio", "\(inspection.audioFileCount)")
            }
            .padding(.top, 2)

            if let failure = inspection.failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }

    // MARK: - Routage

    private var routingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Canaux routés vers ce bus").font(.headline)
                Spacer()
                if inspection.ambiguousRegions > 0 {
                    Label("\(inspection.ambiguousRegions) région(s) ambiguë(s)",
                          systemImage: "arrow.triangle.branch")
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Plusieurs canaux sont à égalité sur le nom : impossible de "
                              + "désigner lequel porte ces régions. Comptées une fois, au "
                              + "niveau du projet.")
                }
            }

            Text("Fermeture transitive : une piste peut traverser un ou plusieurs bus "
                 + "intermédiaires avant d'atteindre le bus cherché.")
                .font(.caption).foregroundStyle(.secondary)

            if inspection.analysis.linkedChannels.isEmpty {
                Label(inspection.analysis.hasBus
                      ? "Aucun canal n'envoie de signal vers ce bus."
                      : "Aucun canal ne porte le nom cherché.",
                      systemImage: "minus.circle")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                Table(inspection.analysis.linkedChannels) {
                    TableColumn("Slot") { channel in
                        Text(String(format: "0x%04x", channel.slot))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    .width(62)

                    TableColumn("Canal") { channel in Text(channel.name) }

                    TableColumn("Rôle") { channel in
                        Label(channel.isIntermediateBus ? "bus intermédiaire" : "piste",
                              systemImage: channel.isIntermediateBus
                                ? "arrow.triangle.merge" : "waveform")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .width(140)

                    TableColumn("Régions") { channel in
                        Text("\(channel.regionCount)")
                            .monospacedDigit()
                            .foregroundStyle(channel.hasAudio ? .green : .secondary)
                    }
                    .width(70)
                }
                .frame(minHeight: 160, maxHeight: 220)
            }
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Analyse audio").font(.headline)
                Text("étage 3, optionnel")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                if inspection.audioAnalysis == nil {
                    Button("Analyser \(inspection.audioFileCount) fichier(s)") { analyzeAudio() }
                        .disabled(inspection.audioFileCount == 0)
                        .controlSize(.small)
                }
            }

            if let report = inspection.audioAnalysis {
                if report.files.isEmpty {
                    Label("Aucun fichier dans Media/Audio Files — le verdict négatif est certain : "
                          + "s'il n'y a aucun audio dans le projet, il n'y en a pas sur le bus.",
                          systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Table(report.files) {
                        TableColumn("Fichier") { file in
                            Text(file.fileName).lineLimit(1).truncationMode(.middle)
                        }
                        TableColumn("Durée") { file in
                            Text(file.duration > 0 ? String(format: "%.1f s", file.duration) : "—")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .width(66)
                        TableColumn("Crête") { file in
                            Text(file.peakDB.isFinite ? String(format: "%.1f dB", file.peakDB) : "−∞")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .width(78)
                        TableColumn("Résultat") { file in
                            Text(file.summary)
                                .foregroundStyle(file.containsVocal ? .green : .secondary)
                        }
                        .width(120)
                        TableColumn("Libellés du classifieur") { file in
                            Text(file.labels.isEmpty
                                 ? "—"
                                 : file.labels.map { "\($0.identifier) \(Int($0.confidence * 100))%" }
                                     .joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .frame(minHeight: 120, maxHeight: 180)

                    Text("Les libellés sont ceux du classifieur système, affichés bruts : si un "
                         + "libellé vocal n'est pas reconnu, il suffit de l'ajouter à la liste "
                         + "des jetons vocaux.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(inspection.audioFileCount == 0
                     ? "Aucun fichier audio à analyser."
                     : "Non lancée. Décoder l'audio coûte environ une seconde par fichier, "
                       + "contre une dizaine de millisecondes pour lire le ProjectData.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Pied

    private var footer: some View {
        HStack {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([inspection.url])
            } label: {
                Label("Révéler dans le Finder", systemImage: "folder")
            }
            Button {
                NSWorkspace.shared.open(inspection.url)
            } label: {
                Label("Ouvrir dans Logic", systemImage: "arrow.up.forward.app")
            }
            .help("Pour trancher à la main les cas que l'analyse ne peut pas conclure.")
            Spacer()
            Button("Fermer") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }
}
