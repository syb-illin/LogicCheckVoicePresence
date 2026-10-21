<div align="center">

# Logic Check Voice Presence

**Votre bus « voice » porte-t-il vraiment de l'audio ?**

Scanne un dossier de projets Logic Pro et répond projet par projet, en lisant le
routage du mixeur directement dans le binaire du projet.

[![CI](https://github.com/syb-illin/LogicCheckVoicePresence/actions/workflows/ci.yml/badge.svg)](https://github.com/syb-illin/LogicCheckVoicePresence/actions/workflows/ci.yml)
[![Couverture](https://img.shields.io/badge/couverture-82.9%25-green?style=flat-square)](https://github.com/syb-illin/LogicCheckVoicePresence/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/syb-illin/LogicCheckVoicePresence?style=flat-square&color=blue)](https://github.com/syb-illin/LogicCheckVoicePresence/releases/latest)
[![Téléchargements](https://img.shields.io/github/downloads/syb-illin/LogicCheckVoicePresence/total?style=flat-square)](https://github.com/syb-illin/LogicCheckVoicePresence/releases)

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native-0071e3?style=flat-square)](https://developer.apple.com/xcode/swiftui/)
[![Licence](https://img.shields.io/badge/licence-MIT-green?style=flat-square)](LICENSE)

[**Télécharger**](https://github.com/syb-illin/LogicCheckVoicePresence/releases/latest) ·
[Comment ça marche](#comment-ça-marche) ·
[Le format binaire](#le-format-binaire-de-logic) ·
[Développement](#développement)

</div>

---

## Le problème

Vous avez des centaines de projets Logic. Beaucoup contiennent un bus nommé
« voice bus ». Dans certains, il porte le chant. Dans d'autres, il a été créé,
nommé, équipé de plugins… et rien n'a jamais été enregistré dessus.

Ouvrir chaque projet pour vérifier prend des heures. Et Logic **ne journalise
rien** : aucune API, aucun fichier, aucune métadonnée ne dit si un bus porte de
l'audio. L'information n'existe que dans le binaire propriétaire du projet.

Cette app l'y lit.

## Ce qu'elle répond

| Verdict | Sens | Certitude |
|---|---|---|
| **Bus + audio** | Au moins une région est rattachée de façon certaine à un canal routé vers le bus | Élevée |
| **Bus + audio (probable)** | Des régions se rattachent au bus, mais plusieurs canaux sont à égalité sur le nom | Moyenne |
| **Indécidable** | Des canaux alimentent le bus, le projet a des régions et des fichiers audio, mais aucun nom ne concorde | À trancher par l'analyse audio |
| **Bus sans audio** | Des canaux alimentent le bus et rien ne peut leur être rattaché | Élevée |
| **Bus orphelin** | Le bus existe, aucun canal n'y envoie de signal | Certaine |
| **Pas de bus** | Aucun canal ne porte le nom cherché | Certaine |

Le nom du bus est configurable : `voice bus` par défaut, mais `drum bus`,
`Guitar bus` ou n'importe quoi d'autre fonctionne. Comparaison par inclusion,
casse ignorée.

## Comment ça marche

Trois étages, de coûts très différents. **Les deux premiers tournent toujours,
le troisième jamais sans votre accord.**

```
┌─ Étage 1 ─ Binaire ProjectData ────────────────── ~10 ms / projet ─┐
│  Décode les canaux du mixeur, leur nom et leur routage.            │
│  Remonte la chaîne jusqu'au bus par fermeture transitive.          │
│  Rattache les régions audio aux canaux.                            │
└────────────────────────────────────────────────────────────────────┘
┌─ Étage 2 ─ Inventaire disque ───────────────────── négligeable ────┐
│  Compte les fichiers de Media/Audio Files. Aucun décodage.         │
│  Rend le verdict négatif inattaquable : aucun fichier audio dans   │
│  le projet ⇒ aucun audio sur le bus, nécessairement.               │
└────────────────────────────────────────────────────────────────────┘
┌─ Étage 3 ─ Contenu audio (optionnel) ────────────── ~1 s / fichier ┐
│  AVFoundation mesure la crête ; SoundAnalysis classe le contenu.   │
│  Lancé à la main, sur les seuls projets « Indécidable ».           │
│  Aucune dépendance : frameworks système, tout en local.            │
└────────────────────────────────────────────────────────────────────┘
```

Sur un corpus réel de **791 projets**, l'étage 1 prend quelques secondes et
laisse une poignée de cas indécidables — c'est là, et seulement là, que décoder
de l'audio sert à quelque chose.

### La subtilité qui fait tout

Un bus nommé reçoit rarement les pistes directement :

```
voice verse 1 ─┐
voice verse 2 ─┼──▶ Verse bus  ─┐
voice verse 3 ─┘                ├──▶ Voice bus
voice chorus L ┐                │
voice chorus R ┼──▶ Chorus bus ─┘
voice chorus C ┘
```

Chercher les canaux pointant *directement* sur `Voice bus` ne trouve que deux
bus intermédiaires et **zéro piste** — et conclut à tort « bus sans audio ».
D'où la fermeture transitive du graphe de routage.

## Installation

### Téléchargement

Récupérez la dernière archive sur la
[page des releases](https://github.com/syb-illin/LogicCheckVoicePresence/releases/latest),
décompressez, glissez l'app dans *Applications*.

> **Premier lancement** : clic droit sur l'app → **Ouvrir** → *Ouvrir*.
> L'app est signée ad hoc, pas notarisée : macOS demande une confirmation
> explicite la première fois, puis plus jamais.

### Compilation depuis les sources

Nécessite les *Command Line Tools* Xcode (`xcode-select --install`) — l'IDE
complet n'est pas requis.

```bash
git clone https://github.com/syb-illin/LogicCheckVoicePresence.git
cd LogicCheckVoicePresence
./Scripts/build-app.sh
open build/LogicCheckVoicePresence.app
```

## Utilisation

1. **Choisissez un dossier** de projets `.logicx` (ou déposez-le sur la fenêtre).
2. Ajustez le **nom du bus** si besoin.
3. Lisez les verdicts, filtrez par pastille dans la barre latérale.
4. Double-cliquez un projet pour voir **la chaîne de routage reconstruite** :
   chaque canal retenu, son rôle (piste ou bus intermédiaire), son compte de
   régions.
5. Si des projets sortent **Indécidable**, lancez l'analyse audio depuis la
   barre d'outils — elle ne traitera que ceux-là.
6. **Exportez en CSV** pour traiter les résultats ailleurs.

L'app affiche systématiquement *sur quoi* repose un verdict : rien n'est
présenté comme une boîte noire, et vous pouvez la contredire.

## Le format binaire de Logic

Le `ProjectData` d'un `.logicx` est un blob propriétaire **non compressé**,
découpé en chunks repérés par un FourCC écrit à l'envers. Apple n'en documente
rien.

| Chunk | Sens | Champs exploités |
|---|---|---|
| `ivnE` (`Envi`) | Canal de l'Environment, soit une tranche du mixeur | `+0x0a` slot · `+0x4a` **slot de sortie (routage)** · `+0xc2` nom |
| `gRuA` (`AuRg`) | Région audio | `+0x6e` nom |

Les noms sont des chaînes ASCII préfixées par leur longueur sur 16 bits
petit-boutiste.

### Comment ces offsets ont été établis

`+0x4a` — le champ de routage — a été isolé en **prédisant** la cible sur des
canaux dont le bus était connu par ailleurs : `gratte verse` → `Guitar bus`,
`bass chorus` → `bass bus`, `EPiano verse` → `Piano bus`. Prédictions correctes,
puis cohérence globale vérifiée : dans le graphe reconstruit, chaque piste pointe
vers un bus plausible et chaque bus vers `Not Assigned` ou vers un bus parent.
Validé ensuite sur 791 projets réels, **zéro erreur de décodage**.

### Ce qui n'a pas pu être établi

Le lien **structurel** région → canal n'existe pas sous une forme exploitable.
Vérifié par deux tests indépendants :

1. Aucun offset de `gRuA` ne contient le slot du canal attendu, pour aucune
   région dont le canal était connu par ailleurs.
2. Aucun offset n'est constant au sein d'un groupe de régions partageant un
   canal tout en étant distinct entre groupes — ce qu'un index de piste serait
   nécessairement.

Les chunks `karT` (pistes) sont à longueur variable, donc sans offset fixe, et
`ProjectData` ne contient **aucun chemin de fichier audio** (`.wav` n'y apparaît
jamais). Le rattachement passe donc par le nom, avec une subtilité : Logic fige
le nom d'une région à l'enregistrement, donc renommer la piste ensuite
désynchronise les deux. La comparaison fonctionne dans les deux sens, et chaque
région est mise en concurrence sur *tous* les canaux du projet — c'est cette
concurrence qui évite d'attribuer à tort une région au bus cherché.

> **Limite assumée** : ces offsets sont des constantes *observées*, pas un
> contrat. Une version majeure de Logic peut les décaler. Ils sont tous
> rassemblés dans [`LogicFormat.swift`](Sources/VoicePresenceCore/Format/LogicFormat.swift)
> pour qu'une recalibration se fasse en un seul endroit — les fixtures de test
> lisent ces mêmes constantes.

## Architecture

```
Sources/
├─ VoicePresenceCore/              bibliothèque sans SwiftUI, entièrement testable
│  ├─ Format/
│  │  ├─ ByteReader.swift          lectures à bornes vérifiées sur Data mmappé
│  │  ├─ LogicFormat.swift         les offsets, rassemblés en un point
│  │  └─ ProjectDataParser.swift   binaire → canaux + régions
│  ├─ Analysis/
│  │  ├─ RoutingGraph.swift        topologie, fermeture transitive
│  │  ├─ RegionAttribution.swift   rattachement des régions aux canaux
│  │  ├─ VoiceBusAnalysis.swift    composition des trois briques
│  │  └─ Verdict.swift             la règle métier, isolée
│  ├─ Discovery/
│  │  ├─ ProjectLocator.swift      bundles et alternatives sur disque
│  │  ├─ ProjectInspection.swift   étages 1 et 2 pour un projet
│  │  └─ ScanCoordinator.swift     parallélisme borné, annulation coopérative
│  ├─ Audio/                       étage 3, derrière un protocole
│  └─ Support/                     journaux, version, semver, export
└─ LogicCheckVoicePresence/        l'interface SwiftUI
```

Quelques partis pris :

- **Le cœur ne connaît pas l'interface.** Il n'importe pas SwiftUI et se teste
  sans écran. L'interface ne connaît pas le binaire.
- **Types valeur et fonctions pures** là où c'est possible ; le seul état mutable
  vit dans le modèle de vue, cantonné au `MainActor`, donc sans verrou ni course.
- **Défensif par construction** : toute lecture du binaire est bornée, aucun
  `!`, aucun index nu. Un fichier tronqué, d'une autre version ou d'un autre
  format donne un résultat partiel, jamais un plantage.
- **Parallélisme borné** : une tâche par cœur, pas une par projet — sinon le pic
  mémoire croît avec la taille du corpus.
- **Dépendances injectées** derrière des protocoles (`AudioAnalyzing`,
  `ReleaseFetching`), ce qui permet de tester la logique sans fichier audio ni
  réseau.
- **Journaux via `os.Logger`**, pas `print` : consultables dans Console.app sans
  que l'app paie la mise en forme quand personne n'écoute.

```bash
log stream --predicate 'subsystem == "io.github.sybillin.LogicCheckVoicePresence"'
```

Des *signposts* sont posés sur le scan, le décodage et l'analyse audio : les
étapes apparaissent telles quelles dans Instruments.

## Développement

```bash
swift build                              # compiler
swift test                               # tests
swift test --enable-code-coverage        # tests + couverture
./Scripts/coverage.sh                    # rapport + pourcentage
./Scripts/check-whitespace.sh            # hygiène du source
./Scripts/build-app.sh                   # bundle .app
```

La couverture n'est mesurée que sur `VoicePresenceCore`. Les vues SwiftUI ne
sont pas testées unitairement : les compter ferait chuter un chiffre censé
renseigner sur la logique métier, pas sur la mise en page.

Les tests n'embarquent **aucun projet réel** : ils fabriquent des `ProjectData`
synthétiques reproduisant la disposition des chunks, en lisant les offsets dans
`LogicFormat` plutôt qu'en les recopiant.

### Publier une version

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Le workflow [`release.yml`](.github/workflows/release.yml) lance les tests,
construit le bundle, vérifie que sa version correspond au tag, empaquette avec
`ditto`, calcule l'empreinte SHA-256 et publie la release avec l'archive. Une
version publiée est une version testée.

## Mise à jour automatique

L'app interroge l'API GitHub Releases, compare les versions **sémantiquement**
(`1.10.0 > 1.9.0`, ce qu'une comparaison de chaînes rate), et propose le
téléchargement depuis la fenêtre *À propos*.

Elle ne s'installe pas toute seule, et c'est délibéré : remplacer l'app sans
intervention suppose de vérifier la signature de ce qu'on installe. Sans
*Developer ID* Apple, l'app n'est que signée ad hoc — une mise à jour
automatique installerait un binaire dont l'origine n'est pas vérifiable, et
Gatekeeper rebloquerait le résultat à chaque fois.

Avec un certificat et une notarisation,
[Sparkle](https://sparkle-project.org) devient le bon outil et remplacerait le
vérificateur actuel sans toucher au reste.

## Limites

- Les offsets dépendent de la version de Logic (voir plus haut).
- Une piste dont les régions ont été **renommées à la main** sera comptée à zéro
  région : le rattachement passe par le nom. Le routage, lui, reste structurel
  et fiable.
- La taxonomie du classifieur audio d'Apple n'est pas un contrat stable. L'app
  affiche donc les libellés bruts : si un libellé vocal n'est pas reconnu, il
  suffit de l'ajouter aux jetons vocaux de
  [`AudioAnalysis.swift`](Sources/VoicePresenceCore/Audio/AudioAnalysis.swift).
- Les fichiers de `Media/Audio Files` **survivent à la suppression des régions**.
  Leur simple présence ne prouve donc pas qu'un projet contient de l'audio — ce
  qui est précisément pourquoi l'étage 2 sert à confirmer les verdicts négatifs,
  jamais les positifs.

## Licence

[MIT](LICENSE) © Ren ([@syb-illin](https://github.com/syb-illin))
