#!/usr/bin/env python3
"""Build this project's bundled assets from the Swift project's Resources.

The Swift project's own `tools/build_bundle.py` reads the two upstream sources
and settles every data quirk -- reprints filled in, the two forms of card back
collapsed to one field, the ten promo printings linked to what they reprint.
Its output is the input here, so none of that is re-derived and the two apps
cannot drift on it.

The one thing this script must actually do is transcode. All 7,742 bundled
images are AVIF and Flutter's engine cannot decode AVIF; the only package that
can offers no decode-time downsampling, which is the mechanism the whole memory
budget rests on. So every image is re-encoded as WebP and the two filename
fields in `cards.json` are rewritten to match.

Run with the Python that has Pillow:

    /Users/f2pgod/Documents/spyder312/bin/python tools/build_assets.py
"""

from __future__ import annotations

import argparse
import json
import multiprocessing
import os
import shutil
import sys
import time
from pathlib import Path

from PIL import Image

SWIFT_RESOURCES = Path.home() / "Documents/arkhamdb/ArkhamCards/Resources"
ASSETS = Path(__file__).resolve().parent.parent / "assets"

QUALITY = 80
# Pillow's WebP effort setting. 4 is its default; 6 costs about three times the
# time for under a percent of size on this material.
METHOD = 4

# What the Swift bundle holds, and so what this one must. A mismatch means the
# upstream data moved and the counts in the tests need re-checking rather than
# the assertion needing relaxing.
EXPECTED_CARDS = 5928
EXPECTED_IMAGES = 7742


def transcode(job: tuple[Path, Path]) -> tuple[str, int] | tuple[str, None]:
    """Re-encode one AVIF as WebP. Returns (name, bytes) or (name, None)."""
    source, destination = job
    try:
        with Image.open(source) as image:
            image.load()
            # Card art has no alpha, and RGB avoids WebP writing an alpha
            # channel for images whose mode is merely capable of one.
            image.convert("RGB").save(
                destination, "WEBP", quality=QUALITY, method=METHOD
            )
        return source.name, destination.stat().st_size
    except Exception as error:  # noqa: BLE001 - reported, not swallowed
        print(f"  {source.name}: {type(error).__name__}: {error}", file=sys.stderr)
        return source.name, None


def build_images(force: bool) -> None:
    source_directory = SWIFT_RESOURCES / "CardImages"
    if not source_directory.is_dir():
        sys.exit(
            f"No card images at {source_directory}.\n"
            "Run the Swift project's tools/build_bundle.py first -- CardImages "
            "is 975 MB and is not committed, so a fresh clone has none."
        )

    destination_directory = ASSETS / "CardImages"
    destination_directory.mkdir(parents=True, exist_ok=True)

    sources = sorted(source_directory.glob("*.avif"))
    jobs = []
    skipped = 0
    for source in sources:
        destination = destination_directory / f"{source.stem}.webp"
        # Transcoding all of them takes a couple of minutes, which is long
        # enough to be worth not repeating for the sake of one changed card.
        if not force and destination.exists():
            if destination.stat().st_mtime >= source.stat().st_mtime:
                skipped += 1
                continue
        jobs.append((source, destination))

    print(f"{len(sources)} images: {len(jobs)} to transcode, {skipped} up to date")

    written = 0
    failed: list[str] = []
    if jobs:
        started = time.monotonic()
        with multiprocessing.Pool() as pool:
            for index, (name, size) in enumerate(
                pool.imap_unordered(transcode, jobs, chunksize=16), start=1
            ):
                if size is None:
                    failed.append(name)
                else:
                    written += size
                if index % 500 == 0 or index == len(jobs):
                    elapsed = time.monotonic() - started
                    print(f"  {index}/{len(jobs)}  {elapsed:.0f}s")

    if failed:
        sys.exit(f"{len(failed)} images failed to transcode: {failed[:10]}")

    # Images the Swift bundle no longer carries would otherwise linger here and
    # be shipped, since the asset directory is declared wholesale in pubspec.
    expected_names = {f"{source.stem}.webp" for source in sources}
    for stale in destination_directory.glob("*.webp"):
        if stale.name not in expected_names:
            stale.unlink()
            print(f"  removed stale {stale.name}")

    total = sum(path.stat().st_size for path in destination_directory.glob("*.webp"))
    count = len(list(destination_directory.glob("*.webp")))
    print(f"{count} images, {total / 1e9:.2f} GB")

    if count != EXPECTED_IMAGES:
        print(
            f"warning: expected {EXPECTED_IMAGES} images, bundled {count}. "
            "If the upstream data changed, update EXPECTED_IMAGES here and the "
            "matching counts in the tests.",
            file=sys.stderr,
        )


def build_cards() -> None:
    """Copy cards.json, pointing its two filename fields at the WebP files."""
    source = SWIFT_RESOURCES / "cards.json"
    if not source.is_file():
        sys.exit(f"No cards.json at {source}")

    cards = json.loads(source.read_text())
    if len(cards) != EXPECTED_CARDS:
        print(
            f"warning: expected {EXPECTED_CARDS} cards, read {len(cards)}",
            file=sys.stderr,
        )

    referenced: set[str] = set()
    for card in cards:
        for field in ("front_image", "back_image"):
            filename = card.get(field)
            if filename:
                card[field] = f"{Path(filename).stem}.webp"
                referenced.add(card[field])

    # The app shows a placeholder for a card with no art, but a card naming art
    # that is not there would fail silently at decode time instead.
    missing = sorted(
        name for name in referenced if not (ASSETS / "CardImages" / name).is_file()
    )
    if missing:
        sys.exit(
            f"{len(missing)} images named by cards.json are not bundled: "
            f"{missing[:10]}"
        )

    ASSETS.mkdir(parents=True, exist_ok=True)
    (ASSETS / "cards.json").write_text(
        json.dumps(cards, ensure_ascii=False, separators=(",", ":"))
    )
    print(f"{len(cards)} cards, {len(referenced)} images referenced")


def build_decks() -> None:
    source = SWIFT_RESOURCES / "decks.json"
    if not source.is_file():
        sys.exit(f"No decks.json at {source}")
    ASSETS.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, ASSETS / "decks.json")
    print(f"{len(json.loads(source.read_text()))} starter decks")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force", action="store_true", help="re-transcode images that already exist"
    )
    parser.add_argument(
        "--skip-images", action="store_true", help="rebuild the JSON only"
    )
    arguments = parser.parse_args()

    if not arguments.skip_images:
        build_images(force=arguments.force)
    build_cards()
    build_decks()


if __name__ == "__main__":
    main()
