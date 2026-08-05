#!/bin/sh
# Attach the transcoded card art to a GitHub Release, so CI can build without it.
#
# The images cannot be rebuilt on a runner: tools/build_assets.py reads two
# upstream checkouts, ~1 GB between them, that live only on this machine. So
# the transcoded WebPs are what has to travel, and a release asset is the only
# place on GitHub that holds 1.13 GiB without metering storage or bandwidth.
# assets/CardImages/ stays gitignored and the repository stays 2 MB.
#
# Run after tools/build_assets.py changes what it writes, bumping TAG.
set -eu

TAG="${TAG:-card-images-v2}"
ASSETS="assets/CardImages"
# What build_assets.py expects to have written. A mismatch means the upstream
# data moved, and cards.json must be republished with the art rather than the
# two drifting apart.
EXPECTED_IMAGES=7617

if [ ! -d "$ASSETS" ]; then
    echo "No card art at $ASSETS. Run tools/build_assets.py first." >&2
    exit 1
fi

count=$(find "$ASSETS" -type f -name '*.webp' | wc -l | tr -d ' ')
if [ "$count" -ne "$EXPECTED_IMAGES" ]; then
    echo "$ASSETS holds $count images, expected $EXPECTED_IMAGES." >&2
    echo "Re-run tools/build_assets.py, or update EXPECTED_IMAGES here, in" >&2
    echo "build_assets.py, in the workflow and in the tests together." >&2
    exit 1
fi

BUILD="${TMPDIR:-/tmp}/arkham-publish"
TARBALL="$BUILD/CardImages.tar"
mkdir -p "$BUILD"

# Uncompressed on purpose: these are WebP already, and gzip measured at 1.5%
# off 1.13 GiB for minutes of CPU on both ends.
echo "packing $count images..."
tar cf "$TARBALL" -C assets CardImages
echo "$(du -h "$TARBALL" | cut -f1) tarball"

echo "uploading to $TAG..."
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$TARBALL" --clobber
else
    gh release create "$TAG" "$TARBALL" \
        --title "Card images ($count)" \
        --notes "Transcoded WebP card art, consumed by .github/workflows/build.yml.

Not part of a source checkout: assets/CardImages/ is gitignored. Built by
tools/build_assets.py and published by tools/publish_assets.sh."
fi

rm -f "$TARBALL"
echo "published $TAG"
