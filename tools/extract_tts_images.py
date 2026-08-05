#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Cut card art out of Tabletop Simulator sprite sheets.

Writes one PNG per card code into a staging directory, which
`tools/build_assets.py` then transcodes to WebP. Replaces the loose copy of
arkhamhorror.app's card directory this project used to read: that tree had no
remote, no tag and no way to reproduce it, and the script that populated it read
the tree it was replacing to decide what to write.

Reads:
  <TTS>/Saves/Arkham SCE 4.8.0.json  - the player cards
  boxes/*.json                       - the official FFG campaign boxes (SCED)
  <TTS>/Mods/Images, sheets/         - the sprite sheets, already cached
  arkhamdb-json-data                 - which codes are wanted, and their type
  tools/swap_list.json               - which cards TTS stores back-to-front

TTS stores cards as cells in a sprite sheet. `CardID` encodes both which sheet
(`str(CardID)[:-2]`, a key into `CustomDeck`) and which cell (`CardID % 100`, a
position in a NumWidth x NumHeight grid). The ArkhamDB code lives in `GMNotes`.

**Runs offline.** Every sheet the official boxes reference is already in one of
the two caches, so nothing is fetched. A sheet that is genuinely absent is
reported and its cards fall back to text in the app rather than being downloaded
-- keeping this pipeline, and the app, free of a network dependency.

Descended from a script by Diablokin (`extract_card_images.py`); the sides and
generic-back rules below are its measurements, kept because they were expensive
to establish.
"""

from __future__ import annotations

import argparse
import csv
import glob
import json
import os
import re
import sys
from collections import Counter, defaultdict

from PIL import Image

import build_assets

HERE = os.path.dirname(os.path.abspath(__file__))
HOME = os.path.expanduser('~')

TTS = os.path.join(HOME, 'Library/Tabletop Simulator')
SAVE_FILE = os.environ.get(
    'ARKHAM_TTS_SAVE', os.path.join(TTS, 'Saves/Arkham SCE 4.8.0.json'))

# Where the sprite sheets already are. Mods/Images is what TTS itself caches
# (and what tts_json_backup.py tops up); the second holds the sheets belonging
# to boxes never opened in-game, which is most of the encounter card art.
SHEET_DIRS = (
    os.path.join(TTS, 'Mods/Images'),
    os.environ.get('ARKHAM_TTS_SHEETS',
                   os.path.join(HOME, 'Downloads/arkham/_sheets')),
)

# The SCED download-box JSON, one file per campaign. Cached by the upstream
# script from github.com/Chr1Z93/SCED-downloads.
BOX_DIR = os.environ.get('ARKHAM_TTS_BOXES',
                         os.path.join(HOME, 'Downloads/arkham/_boxes'))

# Staging, not assets/: build_assets.py transcodes from here, and keeping the
# two apart means a bad extraction never overwrites the shipped art.
OUT_DIR = os.environ.get('ARKHAM_TTS_OUT',
                         os.path.join(HOME, 'Downloads/arkham-tts'))

REPORT = os.path.join(OUT_DIR, 'extraction.csv')
SWAP_LIST = os.path.join(HERE, 'swap_list.json')

OFFICIAL_AUTHOR = 'Fantasy Flight Games'
OFFICIAL_TYPES = ('campaign', 'scenario')
CARD_NAMES = ('Card', 'CardCustom')

# The types whose art is printed landscape. The same rule as `Card.isLandscape`
# in the app, and the reason no perceptual hash is needed here: checked against
# the 7,742 images of the old source, it agreed on 7,739 -- so it is a better
# orientation reference than the pictures were, and it needs no pictures.
LANDSCAPE_TYPES = ('investigator', 'act', 'agenda')

# Below this a crop is not a card. It catches the stale-grid case handled in
# `cell_grid`, and any future sheet whose layout has changed: 54 slivers went
# unnoticed into the old pipeline because nothing downstream checked.
MIN_CARD_PX = 300

# What a card's width-over-height comes out at, either way up. Real art runs
# 750x1050 and 1050x750, so 1.40; the band allows the handful of odd sizes
# (716x1030 is 1.44) without admitting a half-card.
CARD_RATIO = (1.28, 1.52)

# TTS only sets `UniqueBack` on some of the cards that really have their own
# back, so a back is also kept when its image merely differs from the face.
# Guarding that with a share count keeps out the generic backs -- 30 URLs
# covering 11,909 cards between them. Measured against arkhamhorror.app, which
# publishes which cards have two sides:
#
#   rule                                    emitted   missed
#   UniqueBack only                            4118      182
#   back != face                              13455        0  (9813 spurious)
#   UniqueBack or (differs and shared <= 20)   4318       26
GENERIC_BACK_THRESHOLD = 20

# Sprite sheets are legitimately huge (7500x7350 and up).
Image.MAX_IMAGE_PIXELS = None


def log(message):
    print(message, flush=True)


def sheet_filename(url):
    """TTS's cache name for a URL: punctuation stripped, no extension."""
    return re.sub(r'[\/\:\-\_\.\?\=\%]', '', url)


def find_sheet(url):
    """The cached sprite sheet for a URL, or None."""
    stem = sheet_filename(url)
    for folder in SHEET_DIRS:
        matches = glob.glob(os.path.join(folder, stem + '.*'))
        if matches:
            return matches[0]
    return None


def wanted_cards():
    """Every image stem the app could want, mapped to whether it is landscape.

    Derived from the pack files rather than from `assets/cards.json`, which is
    build_assets.py's output: reading that would make each script depend on the
    other's last run. The two agree by construction, because both take a
    front's stem from `code` and a back's from `back_link`/`double_sided`.
    """
    cards = build_assets.load_pack_cards()
    build_assets.resolve_reprints(cards)

    wanted = {}
    for code, card in cards.items():
        landscape = card.get('type_code') in LANDSCAPE_TYPES
        wanted[code] = landscape
        back = card.get('back_link')
        if not back and card.get('double_sided'):
            back = code + 'b'
        if back:
            wanted[back] = landscape
    return wanted


def load_boxes():
    """The official FFG campaign boxes, as (name, data) pairs.

    Read from the local cache only. The library manifest names which of the 191
    SCED entries are official, and is itself part of that cache.
    """
    manifest = os.path.join(BOX_DIR, 'library.json')
    if not os.path.isfile(manifest):
        log('  ! no library.json in {}; official boxes skipped'.format(BOX_DIR))
        return []

    with open(manifest, encoding='utf8') as handle:
        content = json.load(handle)['content']

    official = sorted(
        entry['filename'] for entry in content
        if entry.get('author') == OFFICIAL_AUTHOR
        and entry.get('type') in OFFICIAL_TYPES
    )

    boxes = []
    for name in official:
        path = os.path.join(BOX_DIR, name + '.json')
        if not os.path.isfile(path):
            log('  ! {} not cached; its cards will be missing'.format(name))
            continue
        with open(path, encoding='utf8') as handle:
            boxes.append((name, json.load(handle)))

    log('  {} of {} official boxes cached'.format(len(boxes), len(official)))
    return boxes


def card_code(node):
    """The ArkhamDB code from an object's GMNotes, or None."""
    notes = node.get('GMNotes') or ''
    if not notes.strip().startswith('{'):
        return None
    try:
        meta = json.loads(notes)
    except ValueError:
        return None
    return meta.get('id') if isinstance(meta, dict) else None


def iter_cards(node, parent_deck=None):
    """Yield every card object, with the CustomDeck entry describing its sheet.

    TTS does not refresh a card's own `CustomDeck` while it sits in a bag, so
    the entry is looked up in the nearest enclosing deck as a fallback -- which
    is what the mod's own AllEncounterCardsBag script does.
    """
    if isinstance(node, dict):
        inherited = node.get('CustomDeck') or parent_deck

        card_id = node.get('CardID')
        if node.get('Name') in CARD_NAMES and card_id is not None:
            key = str(card_id)[:-2]
            own = node.get('CustomDeck') or {}
            yield {
                'code': card_code(node),
                'card_id': card_id,
                'entry': own.get(key) or (parent_deck or {}).get(key),
                'sideways': bool(node.get('SidewaysCard')),
            }

        for key, value in node.items():
            if key == 'CustomDeck':
                continue
            yield from iter_cards(value, inherited)

    elif isinstance(node, list):
        for value in node:
            yield from iter_cards(value, parent_deck)


def collect(sources, wanted):
    """Build the crop list: one task per image to write.

    Deduplicated on (code, CardID, sheet), so an object the mod merely repeats
    collapses to one task while a genuinely different printing keeps its own.
    Only codes the app wants survive, which drops the mod's minicards,
    parallel investigators and extra printings.
    """
    variants = defaultdict(list)
    seen = set()
    skipped = Counter()

    for source, data in sources:
        found = 0
        for card in iter_cards(data):
            code, entry = card['code'], card['entry']
            if not code:
                skipped['no card code in GMNotes'] += 1
                continue
            if entry is None:
                skipped['no CustomDeck entry'] += 1
                continue

            face = entry.get('FaceURL')
            if not face:
                skipped['no FaceURL'] += 1
                continue

            fingerprint = (code, card['card_id'], face)
            if fingerprint in seen:
                continue
            seen.add(fingerprint)

            variants[code].append({
                'code': code,
                'source': source,
                'index': card['card_id'] % 100,
                'width': entry.get('NumWidth') or 1,
                'height': entry.get('NumHeight') or 1,
                'face': face,
                'back': entry.get('BackURL'),
                'unique_back': bool(entry.get('UniqueBack')),
                'sideways': card['sideways'],
            })
            found += 1
        log('  {:<34} {:>6} cards'.format(source, found))

    resolve_sides(variants)

    tasks = []
    for code in sorted(variants):
        # Document order decides which printing wins: the mod lists the
        # canonical one first, and only that one is named after the bare code.
        card = variants[code][0]
        if code in wanted:
            tasks.append(dict(card, url=card['face'], stem=code,
                              landscape=wanted[code]))
        back_stem = code + 'b'
        if card['back'] and back_stem in wanted:
            tasks.append(dict(card, url=card['back'], stem=back_stem,
                              landscape=wanted[back_stem]))

    log('  {} codes seen, {} images to crop'.format(len(variants), len(tasks)))
    for reason, count in skipped.most_common():
        log('    skipped {:<24} {}'.format(reason, count))
    return tasks


def resolve_sides(variants):
    """Drop the backs that are not really backs, and swap the reversed pairs.

    For a two-sided card TTS's `FaceURL` is not always the side the rest of the
    world calls the front -- locations show unrevealed, ArkhamDB shows revealed
    -- and no field in the metadata says which. `swap_list.json` records the
    answer, measured once by comparing the images themselves.
    """
    with open(SWAP_LIST, encoding='utf8') as handle:
        swapped_codes = set(json.load(handle)['swapped'])

    back_usage = Counter()
    for group in variants.values():
        for card in group:
            if card['back']:
                back_usage[card['back']] += 1

    kept = recovered = swapped = 0
    for code, group in variants.items():
        for card in group:
            back = card['back']
            if not back:
                continue
            if card['unique_back']:
                kept += 1
            elif (back != card['face']
                    and back_usage[back] <= GENERIC_BACK_THRESHOLD):
                recovered += 1
            else:
                card['back'] = None
                continue

            if code in swapped_codes:
                card['face'], card['back'] = card['back'], card['face']
                swapped += 1

    log('  backs: {} flagged by TTS, {} recovered, {} pairs swapped'.format(
        kept, recovered, swapped))


def is_card_shaped(size):
    width, height = size
    ratio = max(size) / min(size)
    return min(size) >= MIN_CARD_PX and CARD_RATIO[0] < ratio < CARD_RATIO[1]


def cell_grid(sheet, task):
    """The grid to slice this sheet by, which is not always the declared one.

    54 cards came out as slivers because their sheet holds a single card but
    declares a `3x2` or `7x2` grid -- an edit upstream that split a sheet
    without updating NumWidth/NumHeight.

    The declared grid is believed whenever it yields a card-shaped cell, and
    only a grid that does not is overridden. Testing the *sheet* instead does
    not work: a 4x2 sheet of 750x1050 cards is 3000x2100, whose 1.43 is as
    card-shaped as a card, so 684 whole sheets were written as single cards.
    """
    width = task['width']
    height = task['height']
    cell = (sheet.width // width, sheet.height // height)
    if is_card_shaped(cell) or not is_card_shaped(sheet.size):
        return width, height, task['index']
    return 1, 1, 0


def crop(sheet, task):
    """Cut one card from its sheet, upright."""
    width, height, index = cell_grid(sheet, task)
    cell_w = sheet.width // width
    cell_h = sheet.height // height
    row, column = divmod(index, width)
    left, top = column * cell_w, row * cell_h
    cell = sheet.crop((left, top, left + cell_w, top + cell_h))

    # Investigator and act/agenda art is stored rotated and flagged
    # `SidewaysCard`. The flag is not reliable on its own -- 26 crops came out
    # the wrong way up with it alone -- so the card's type has the last word.
    if (cell.width > cell.height) != task['landscape']:
        cell = cell.rotate(90, expand=True)
    return cell


def extract(tasks, force):
    """Crop every task, opening each sheet once."""
    by_sheet = defaultdict(list)
    for task in tasks:
        by_sheet[task['url']].append(task)

    rows = []
    written = skipped = failed = 0
    total = len(by_sheet)

    for number, (url, group) in enumerate(sorted(by_sheet.items()), start=1):
        pending = group if force else [
            task for task in group
            if not os.path.exists(os.path.join(OUT_DIR, task['stem'] + '.png'))
        ]
        skipped += len(group) - len(pending)
        if not pending:
            continue

        path = find_sheet(url)
        if path is None:
            for task in pending:
                rows.append(report_row(task, 'sheet not cached'))
                failed += 1
            continue

        try:
            with Image.open(path) as sheet:
                sheet.load()
                for task in pending:
                    cell = crop(sheet, task)
                    if not is_card_shaped(cell.size):
                        rows.append(report_row(
                            task, 'implausible crop {}x{}'.format(*cell.size)))
                        failed += 1
                        continue
                    cell.convert('RGB').save(
                        os.path.join(OUT_DIR, task['stem'] + '.png'))
                    rows.append(report_row(task, 'ok'))
                    written += 1
        except Exception as error:  # noqa: BLE001 - reported, not swallowed
            for task in pending:
                rows.append(report_row(
                    task, '{}: {}'.format(type(error).__name__, error)[:80]))
                failed += 1

        if number % 100 == 0 or number == total:
            log('  sheet {}/{}  written {}'.format(number, total, written))

    return rows, written, skipped, failed


def report_row(task, status):
    return {
        'stem': task['stem'],
        'code': task['code'],
        'source': task['source'],
        'cell': task['index'],
        'grid': '{}x{}'.format(task['width'], task['height']),
        'sheet': task['url'],
        'status': status,
    }


def write_report(rows):
    fields = ['stem', 'code', 'source', 'cell', 'grid', 'sheet', 'status']
    with open(REPORT, 'w', newline='', encoding='utf8') as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--force', action='store_true',
                        help='re-crop cards already written')
    arguments = parser.parse_args()

    for path in (SAVE_FILE, BOX_DIR):
        if not os.path.exists(path):
            log('Missing source: {}'.format(path))
            return 1

    os.makedirs(OUT_DIR, exist_ok=True)

    log('Reading which cards are wanted')
    wanted = wanted_cards()
    log('  {} image stems the app can use'.format(len(wanted)))

    log('Reading Tabletop Simulator data')
    with open(SAVE_FILE, encoding='utf8') as handle:
        sources = [('save', json.load(handle))]
    sources.extend(load_boxes())

    log('Indexing cards')
    tasks = collect(sources, wanted)

    log('Cropping')
    rows, written, already, failed = extract(tasks, arguments.force)
    write_report(rows)

    present = {
        os.path.splitext(name)[0] for name in os.listdir(OUT_DIR)
        if name.endswith('.png')
    }

    log('\nWrote {} cards to {}'.format(written, OUT_DIR))
    log('  already present : {}'.format(already))
    log('  failed          : {}'.format(failed))
    log('  total on disk   : {}'.format(len(present)))
    log('  report          : {}'.format(REPORT))

    # Named, not just counted: the count alone cannot tell a card the mod does
    # not carry from one whose sheet arrived truncated, and only the second is
    # worth acting on. `01693` is the standing example -- its cached sheet is
    # short, and re-downloading it would fix that one card.
    if failed:
        log('\n{} cards could not be cropped:'.format(failed))
        for row in sorted(
                (row for row in rows if row['status'] != 'ok'),
                key=lambda row: row['stem'])[:20]:
            log('    {:<9} {:<28} {}'.format(
                row['stem'], row['source'][:28], row['status'][:44]))

    return 0


if __name__ == '__main__':
    sys.exit(main())
