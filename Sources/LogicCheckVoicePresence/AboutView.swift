import SwiftUI
import AppKit
import VoicePresenceCore

/// Fenêtre « À propos » : version, auteur, et vérification de mise à jour.
struct AboutView: View {
    let model: ScanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text(AppInfo.name).font(.title2.bold())
                Text(AppInfo.versionDisplay)
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text("Détecte si un bus nommé d'un projet Logic Pro porte réellement de l'audio, "
                 + "en lisant le routage du mixeur directement dans le binaire du projet.")
                .font(.callout).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)

            Divider()

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Par").foregroundStyle(.secondary)
                    Text(AppInfo.author).fontWeight(.medium)
                    Link("@\(AppInfo.authorHandle)", destination: AppInfo.authorURL)
                }
                .font(.callout)

                Text(AppInfo.copyright).font(.caption).foregroundStyle(.secondary)
            }

            updateSection

            Divider()

            HStack(spacing: 12) {
                Link(destination: AppInfo.repositoryURL) {
                    Label("Code source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppInfo.issuesURL) {
                    Label("Signaler un problème", systemImage: "exclamationmark.bubble")
                }
            }
            .font(.callout)

            Button("Fermer") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 460)
    }

    // MARK: - Mise à jour

    @ViewBuilder
    private var updateSection: some View {
        VStack(spacing: 8) {
            switch model.updateStatus {
            case .none:
                Button {
                    check()
                } label: {
                    if isChecking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Vérification…")
                        }
                    } else {
                        Text("Vérifier les mises à jour")
                    }
                }
                .disabled(isChecking)

            case .upToDate(let current):
                Label("À jour (\(current.description))", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.green)
                Button("Vérifier à nouveau") { check() }.controlSize(.small)

            case .updateAvailable(let release):
                VStack(spacing: 6) {
                    Label("Version \(release.version.description) disponible",
                          systemImage: "arrow.down.circle.fill")
                        .font(.callout.weight(.medium)).foregroundStyle(.tint)

                    if !release.notes.isEmpty {
                        ScrollView {
                            Text(release.notes)
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 90)
                        .padding(8)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 6))
                    }

                    HStack(spacing: 10) {
                        if let download = release.downloadURL {
                            Link("Télécharger", destination: download)
                                .buttonStyle(.borderedProminent)
                        }
                        Link("Voir la release", destination: release.pageURL)
                    }
                }

            case .failed(let message):
                // Un échec est dit comme tel : afficher « à jour » quand la
                // vérification n'a pas abouti serait un mensonge commode.
                VStack(spacing: 4) {
                    Label("Vérification impossible", systemImage: "wifi.exclamationmark")
                        .font(.callout).foregroundStyle(.orange)
                    Text(message).font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button("Réessayer") { check() }.controlSize(.small)
            }
        }
        .animation(.default, value: model.updateStatus)
    }

    private func check() {
        guard !isChecking else { return }
        isChecking = true
        Task { @MainActor in
            await model.checkForUpdates()
            isChecking = false
        }
    }
}
