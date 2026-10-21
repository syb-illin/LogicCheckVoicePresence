#!/usr/bin/env python3
"""Réécrit le badge de couverture du README.

Badge statique plutôt qu'endpoint dynamique : un endpoint devrait lire un
fichier du dépôt, ce qui échoue tant que le dépôt est privé. Un badge dont la
valeur est écrite dans l'URL fonctionne dans les deux cas.

Usage : update_coverage_badge.py <pourcentage> [chemin_readme]
Sortie : code 0 si le fichier a changé ou était déjà à jour, 1 en cas d'erreur.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

BADGE_PATTERN = re.compile(r"https://img\.shields\.io/badge/couverture-[^)\s]+")


def color_for(percent: float) -> str:
    """Seuils de couleur, du plus exigeant au plus permissif."""
    if percent >= 90:
        return "brightgreen"
    if percent >= 75:
        return "green"
    if percent >= 60:
        return "yellow"
    if percent >= 40:
        return "orange"
    return "red"


def badge_url(percent: float) -> str:
    return (
        f"https://img.shields.io/badge/couverture-{percent:.1f}%25-"
        f"{color_for(percent)}?style=flat-square"
    )


def main(argv: list[str]) -> int:
    if not 2 <= len(argv) <= 3:
        print(__doc__, file=sys.stderr)
        return 1

    try:
        percent = float(argv[1])
    except ValueError:
        print(f"Pourcentage illisible : {argv[1]!r}", file=sys.stderr)
        return 1

    readme = Path(argv[2] if len(argv) == 3 else "README.md")
    if not readme.is_file():
        print(f"README introuvable : {readme}", file=sys.stderr)
        return 1

    original = readme.read_text(encoding="utf-8")
    if not BADGE_PATTERN.search(original):
        print("Aucun badge de couverture trouvé dans le README", file=sys.stderr)
        return 1

    updated = BADGE_PATTERN.sub(badge_url(percent), original)
    if updated == original:
        print(f"Badge déjà à jour ({percent:.1f}%)")
        return 0

    readme.write_text(updated, encoding="utf-8")
    print(f"Badge mis à jour : {percent:.1f}% ({color_for(percent)})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
