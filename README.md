<div align="center">

# Logic Check Voice Presence

**Votre bus « voice » porte-t-il vraiment de l'audio ?**

Scanne un dossier entier de projets Logic Pro et répond projet par projet.

[![CI](https://github.com/syb-illin/LogicCheckVoicePresence/actions/workflows/ci.yml/badge.svg)](https://github.com/syb-illin/LogicCheckVoicePresence/actions/workflows/ci.yml)
[![Couverture](https://img.shields.io/badge/couverture-82.9%25-green?style=flat-square)](https://github.com/syb-illin/LogicCheckVoicePresence/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/syb-illin/LogicCheckVoicePresence?style=flat-square&color=blue)](https://github.com/syb-illin/LogicCheckVoicePresence/releases/latest)
[![Téléchargements](https://img.shields.io/github/downloads/syb-illin/LogicCheckVoicePresence/total?style=flat-square)](https://github.com/syb-illin/LogicCheckVoicePresence/releases)

[![macOS](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Licence](https://img.shields.io/badge/licence-MIT-green?style=flat-square)](LICENSE)

### [⬇ Télécharger la dernière version](https://github.com/syb-illin/LogicCheckVoicePresence/releases/latest)

</div>

---

## Le problème

Vous avez des centaines de projets Logic. Beaucoup contiennent un bus nommé
« voice bus ». Dans certains il porte le chant ; dans d'autres il a été créé,
nommé, équipé de plugins, et **rien n'a jamais été enregistré dessus**.

Ouvrir chaque projet pour vérifier prend des heures, et Logic n'expose aucune
information permettant de le savoir sans l'ouvrir.

Cette app répond pour tout un dossier, en quelques secondes.

## Les verdicts

| | Verdict | Ce que ça veut dire |
|---|---|---|
| 🟢 | **Bus + audio** | Des régions audio sont rattachées de façon certaine à une piste routée vers le bus |
| 🟩 | **Bus + audio (probable)** | Des régions se rattachent au bus, mais plusieurs pistes portent des noms trop proches pour désigner laquelle |
| 🔵 | **Indécidable** | Des pistes alimentent le bus et le projet contient de l'audio, mais aucun nom ne concorde. L'analyse audio peut trancher |
| 🟠 | **Bus sans audio** | Des pistes alimentent le bus, et rien dans le projet ne peut leur être rattaché |
| 🟡 | **Bus orphelin** | Le bus existe dans le mixeur, mais aucune piste n'y envoie de signal |
| ⚪ | **Pas de bus** | Aucune tranche du mixeur ne porte le nom cherché |

Le nom recherché est libre : `voice bus` par défaut, mais `drum bus`,
`Guitar bus` ou tout autre nom fonctionne. La recherche se fait par inclusion,
sans tenir compte de la casse.

L'app suit les **chaînes de bus à plusieurs niveaux** : une piste qui passe par
un bus de couplet, lui-même routé vers le bus voix, est correctement rattachée.

## Installation

1. Téléchargez l'archive sur la
   [page des releases](https://github.com/syb-illin/LogicCheckVoicePresence/releases/latest).
2. Décompressez, glissez **LogicCheckVoicePresence.app** dans *Applications*.
3. Au premier lancement : **clic droit sur l'app → Ouvrir**, puis confirmez.

> L'app n'est pas notarisée par Apple : macOS demande une confirmation explicite
> la première fois, puis plus jamais. Chaque release publie l'empreinte SHA-256
> de son archive si vous souhaitez la vérifier.

**Configuration requise** : macOS 14 (Sonoma) ou plus récent.

### Compiler depuis les sources

Nécessite les *Command Line Tools* Xcode (`xcode-select --install`) ; l'IDE
complet n'est pas requis.

```bash
git clone https://github.com/syb-illin/LogicCheckVoicePresence.git
cd LogicCheckVoicePresence
./Scripts/build-app.sh
open build/LogicCheckVoicePresence.app
```

## Utilisation

1. **Choisissez un dossier** de projets `.logicx`, ou déposez-le sur la fenêtre.
2. Ajustez le **nom du bus** recherché si besoin.
3. Parcourez les résultats, filtrez par verdict depuis la barre latérale.
4. **Double-cliquez un projet** pour voir le détail : chaque piste retenue, son
   rôle dans la chaîne, et le nombre de régions audio rattachées.
5. **Exportez en CSV** pour traiter les résultats ailleurs.

Chaque verdict indique ce sur quoi il repose : vous pouvez vérifier, et
contredire, ce que l'app affiche.

### Analyse audio

Les projets classés **Indécidable** se tranchent en inspectant le contenu des
fichiers audio. Cette étape se lance **à la demande**, depuis la barre d'outils,
et ne traite que ces projets : décoder de l'audio prend environ une seconde par
fichier, là où le reste du scan en prend quelques millisecondes par projet. Elle
n'est jamais déclenchée automatiquement.

L'analyse est entièrement locale et n'envoie rien sur le réseau.

## Mises à jour

L'app vérifie au lancement si une version plus récente existe et vous le signale
dans la fenêtre **À propos**, d'où vous pouvez la télécharger. Elle ne s'installe
jamais d'elle-même : vous gardez la main sur ce qui est installé.

## Bon à savoir

- Une piste dont les **régions ont été renommées à la main** peut être comptée à
  zéro région. Le projet apparaît alors en *Indécidable* plutôt qu'en *Bus +
  audio* — l'analyse audio lève le doute.
- Les fichiers audio **restent sur le disque après la suppression des régions**
  qui les utilisaient. Leur seule présence ne prouve donc pas qu'un projet
  contient de l'audio.
- L'app lit les projets **sans jamais les modifier**. Elle n'ouvre rien dans
  Logic et ne touche à aucun fichier.
- Une mise à jour majeure de Logic Pro peut changer le format interne des
  projets. Si les résultats deviennent incohérents après une telle mise à jour,
  [ouvrez un ticket](https://github.com/syb-illin/LogicCheckVoicePresence/issues).

## Licence

[MIT](LICENSE) © Ren ([@syb-illin](https://github.com/syb-illin))
