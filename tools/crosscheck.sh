#!/bin/sh
# Diff what the Dart models compute against what the Swift ones do.
#
# The ported tests prove Dart agrees with assertions someone wrote down. They
# cannot prove it agrees with the Swift app being replaced -- an ordering rule
# read slightly wrong would satisfy both. This builds the Swift models straight
# out of the original repo, runs the same dump through each, and diffs them.
#
# Expects the Swift project beside this one. Exits non-zero on any difference.
set -eu

SWIFT_REPO="${SWIFT_REPO:-$HOME/Documents/arkhamdb}"
MODELS="$SWIFT_REPO/ArkhamCards/Models"
RESOURCES="$SWIFT_REPO/ArkhamCards/Resources"
BUILD="${TMPDIR:-/tmp}/arkham-crosscheck"

if [ ! -d "$MODELS" ]; then
    echo "No Swift models at $MODELS. Set SWIFT_REPO." >&2
    exit 1
fi

mkdir -p "$BUILD"
cp tools/swift_dump/main.swift tools/swift_dump/stub.swift "$BUILD/"

echo "building the Swift dump..."
swiftc -O -o "$BUILD/dump" \
    "$BUILD/main.swift" "$BUILD/stub.swift" \
    "$MODELS/Card.swift" "$MODELS/CardDatabase.swift" \
    "$MODELS/CardQuery.swift" "$MODELS/Deck.swift" \
    "$MODELS/DeckContents.swift"

echo "dumping..."
"$BUILD/dump" "$RESOURCES" > "$BUILD/swift.txt"
dart run tools/dump_dart.dart > "$BUILD/dart.txt"

if diff -u "$BUILD/swift.txt" "$BUILD/dart.txt" > "$BUILD/diff.txt"; then
    echo "identical: $(wc -l < "$BUILD/swift.txt" | tr -d ' ') lines"
else
    echo "DIFFERENCES -- $BUILD/diff.txt" >&2
    head -40 "$BUILD/diff.txt" >&2
    exit 1
fi
