#!/bin/sh
# Unpack the card art into assets/, for a CI runner that has just checked out.
#
# assets/CardImages/ is gitignored and cannot be rebuilt here -- see
# tools/publish_assets.sh for why it arrives as a release asset instead.
#
# Both jobs in build.yml run this, and both have 14 GB of disk against a
# tarball that expands to as much again, so it is deleted the moment it has
# been read.
set -eu

: "${IMAGES_TAG:?not set}"
: "${EXPECTED_IMAGES:?not set}"

echo "downloading $IMAGES_TAG..."
gh release download "$IMAGES_TAG" --pattern CardImages.tar --dir .

tar xf CardImages.tar -C assets
rm -f CardImages.tar

count=$(find assets/CardImages -type f -name '*.webp' | wc -l | tr -d ' ')
if [ "$count" -ne "$EXPECTED_IMAGES" ]; then
    echo "unpacked $count images, expected $EXPECTED_IMAGES." >&2
    echo "The tarball and cards.json have drifted; republish with" >&2
    echo "tools/publish_assets.sh." >&2
    exit 1
fi

echo "$count images unpacked"
df -h /
