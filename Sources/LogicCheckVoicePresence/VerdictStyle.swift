import SwiftUI
import VoicePresenceCore

/// Représentation visuelle d'un verdict.
///
/// Séparé des vues : la couleur et le symbole d'un verdict sont une décision de
/// présentation unique, qui ne doit pas être recopiée dans chaque vue.
///
/// Chaque verdict porte une couleur **et** un symbole : la couleur seule ne
/// suffit pas à distinguer les états pour une personne daltonienne.
enum VerdictStyle {

    static func color(_ verdict: Verdict) -> Color {
        switch verdict {
        case .busWithAudio: .green
        case .busProbableAudio: .mint
        case .undecidable: .blue
        case .busNoAudio: .orange
        case .busOrphan: .yellow
        case .noBus: .secondary
        case .unreadable: .red
        }
    }

    static func symbol(_ verdict: Verdict) -> String {
        switch verdict {
        case .busWithAudio: "checkmark.circle.fill"
        case .busProbableAudio: "checkmark.circle"
        case .undecidable: "questionmark.circle.fill"
        case .busNoAudio: "exclamationmark.triangle.fill"
        case .busOrphan: "link.badge.plus"
        case .noBus: "minus.circle"
        case .unreadable: "xmark.octagon.fill"
        }
    }

    /// Libellé court pour les pastilles de filtre.
    static func shortLabel(_ verdict: Verdict) -> String {
        switch verdict {
        case .busWithAudio: "Avec audio"
        case .busProbableAudio: "Probable"
        case .undecidable: "Indécidable"
        case .busNoAudio: "Sans audio"
        case .busOrphan: "Orphelin"
        case .noBus: "Pas de bus"
        case .unreadable: "Illisible"
        }
    }
}

/// Pastille d'un verdict, réutilisée dans la table et dans le détail.
struct VerdictBadge: View {
    let verdict: Verdict
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: VerdictStyle.symbol(verdict))
                .foregroundStyle(VerdictStyle.color(verdict))
                .font(.caption)
            Text(compact ? VerdictStyle.shortLabel(verdict) : verdict.rawValue)
                .lineLimit(1)
        }
        .accessibilityLabel(verdict.rawValue)
        .help(verdict.rationale)
    }
}
