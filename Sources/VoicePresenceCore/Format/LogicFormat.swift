import Foundation

/// Disposition du binaire `ProjectData` d'un bundle `.logicx`.
///
/// ## Ce que c'est
///
/// Un blob binaire propriétaire, **non compressé**, découpé en chunks repérés
/// par un FourCC écrit à l'envers (`ivnE` pour `Envi`, `gRuA` pour `AuRg`,
/// `karT` pour `Trak`…). Apple ne documente rien de tout cela.
///
/// ## Chunks exploités
///
/// | Chunk  | Sens          | Champs utilisés                                   |
/// |--------|---------------|---------------------------------------------------|
/// | `ivnE` | Environment   | `+0x0a` slot, `+0x4a` slot de sortie, `+0xc2` nom |
/// | `gRuA` | AudioRegion   | `+0x6e` nom                                       |
///
/// Les noms sont des chaînes ASCII préfixées par leur longueur sur 16 bits LE.
///
/// ## Comment ces offsets ont été établis
///
/// `+0x4a` (le routage) a été isolé en **prédisant** la cible sur des canaux
/// dont le bus était connu par ailleurs — `gratte verse` → `Guitar bus`,
/// `bass chorus` → `bass bus`, `EPiano verse` → `Piano bus` — puis vérifié par
/// la cohérence globale du graphe reconstruit : chaque piste pointe vers un bus
/// plausible, chaque bus vers `Not Assigned` ou vers un bus parent. Validé
/// ensuite sur 791 projets réels sans une seule erreur de décodage.
///
/// ## Limite assumée
///
/// Ces offsets sont des constantes **observées**, pas un contrat. Une version
/// majeure de Logic peut les décaler. Ils sont tous rassemblés ici pour qu'une
/// recalibration se fasse en un seul endroit — y compris dans les tests, dont
/// les fixtures lisent ces mêmes constantes.
public enum LogicFormat {

    // MARK: - Signatures de chunks

    /// `Envi` inversé — canal de l'Environment, c'est-à-dire une tranche du mixeur.
    public static let channelMagic = Data("ivnE".utf8)
    /// `AuRg` inversé — région audio.
    public static let regionMagic = Data("gRuA".utf8)

    // MARK: - Chunk ivnE (canal)

    /// Identifiant du canal.
    public static let channelSlotOffset = 0x0a
    /// Slot du canal de sortie : c'est le routage. `0` signifie « Not Assigned ».
    public static let channelOutputOffset = 0x4a
    /// Nom personnalisé, préfixé par sa longueur.
    public static let channelNameOffset = 0xc2
    /// Taille minimale pour qu'un chunk soit considéré comme exploitable.
    public static let channelMinimumSize = 0x120

    // MARK: - Chunk gRuA (région)

    /// Nom de la région, préfixé par sa longueur.
    public static let regionNameOffset = 0x6e
    public static let regionMinimumSize = 0x80

    // MARK: - Contraintes communes

    /// Longueur de nom au-delà de laquelle on considère lire du bruit.
    public static let maximumNameLength = 64

    /// Slot signifiant « aucune sortie assignée ».
    public static let unassignedSlot = 0
}
