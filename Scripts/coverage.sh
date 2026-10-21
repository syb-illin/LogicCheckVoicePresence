#!/bin/bash
# Mesure la couverture du cœur analytique après `swift test --enable-code-coverage`.
#
# Les vues SwiftUI sont exclues : elles ne sont pas testées unitairement, et les
# compter ferait chuter un chiffre censé renseigner sur la logique métier, pas
# sur la mise en page.
#
# Écrit coverage-report.txt et coverage.lcov, et affiche le pourcentage de
# lignes couvertes sur la sortie standard.
set -euo pipefail

cd "$(dirname "$0")/.."

IGNORE='(Tests|\.build)/'

BIN_PATH="$(swift build --show-bin-path)"
PROFILE="$BIN_PATH/codecov/default.profdata"

if [ ! -f "$PROFILE" ]; then
    echo "Profil de couverture absent : lance d'abord 'swift test --enable-code-coverage'" >&2
    exit 1
fi

XCTEST="$(find "$BIN_PATH" -maxdepth 1 -name '*.xctest' | head -1)"
if [ -z "$XCTEST" ]; then
    echo "Bundle de test introuvable dans $BIN_PATH" >&2
    exit 1
fi
BINARY="$XCTEST/Contents/MacOS/$(basename "$XCTEST" .xctest)"

xcrun llvm-cov report "$BINARY" \
    -instr-profile="$PROFILE" \
    -ignore-filename-regex="$IGNORE" \
    > coverage-report.txt

xcrun llvm-cov export "$BINARY" \
    -instr-profile="$PROFILE" \
    -ignore-filename-regex="$IGNORE" \
    -format=lcov > coverage.lcov

xcrun llvm-cov export "$BINARY" \
    -instr-profile="$PROFILE" \
    -ignore-filename-regex="$IGNORE" \
    -summary-only \
    | python3 -c 'import json,sys; print(f"{json.load(sys.stdin)["data"][0]["totals"]["lines"]["percent"]:.1f}")'
