#!/bin/bash
# Hygiène minimale du source, sans dépendance externe.
#
# Volontairement limité à ce qui est mécaniquement vérifiable et non discutable :
# espaces en fin de ligne, tabulations, retour à la ligne final. Le style de code
# lui-même relève de la relecture, pas d'un script.
set -uo pipefail

cd "$(dirname "$0")/.."

status=0

while IFS= read -r file; do
    if grep -nE '[[:space:]]+$' "$file" > /dev/null; then
        echo "::error file=$file::espaces en fin de ligne"
        grep -nE '[[:space:]]+$' "$file" | head -5
        status=1
    fi
    if grep -nP '\t' "$file" > /dev/null 2>&1; then
        echo "::error file=$file::tabulation (ce projet utilise des espaces)"
        status=1
    fi
    if [ -s "$file" ] && [ -n "$(tail -c1 "$file")" ]; then
        echo "::error file=$file::pas de retour à la ligne final"
        status=1
    fi
done < <(find Sources Tests -name '*.swift')

if [ "$status" -eq 0 ]; then
    echo "Hygiène du source : rien à signaler"
fi

exit "$status"
