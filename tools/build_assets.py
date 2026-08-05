#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the app's bundled assets from three local sources.

Reads:
  arkhamdb-json-data/                     - 159 pack files, plus packs/cycles/types
  <TTS>/Saves/Arkham SCE <version>.json   - which cards the mod stocks, and where
  ~/Downloads/arkham/_boxes/              - the 37 SCED campaign boxes, same shape
  <TTS>/Mods/Images/                      - the sprite sheets the art is cut from
  ~/Downloads/arkham/_sheets/             - the sheets the boxes name, cached once

Writes:
  assets/cards.json     - every card, merged and annotated
  assets/decks.json     - the 10 Investigator Starter Decks
  assets/CardImages/    - one WebP per referenced code

No source is in this repo and none is version-pinned. `docs/DATA.md` is the
reference for their shape; most of what looks over-complicated below is
explained there. The guiding rule: **settle a data quirk here, so the Dart
model does not carry a special case for it.**

**The save stocks the player cards; the boxes carry everything else.** The
save file alone reaches 2,174 images -- no location, act, agenda, enemy or
treachery. The 37 SCED campaign box JSONs are the same TTS object tree and are
walked by the same `iter_cards`, adding the encounter side. The save is listed
first, so where a code appears in both (167 do, one with a different sheet) the
save's printing wins and the player-card crops stay byte-identical. Both box
directories live outside the TTS tree and are unversioned -- see `docs/DATA.md`
for what that costs and why it was once cut.

The crop writes WebP directly. The sheets arrive as JPEG, PNG and AVIF, and
Flutter's engine decodes none of them the way this app needs -- the one AVIF
package offers no decode-time downsampling, which is the mechanism the whole
memory budget rests on. Going via a PNG staging tree only cost a generation and
9 GB of disk. Each card records the WebP filename, so nothing at runtime has to
guess an extension or stat the filesystem.

Run with the Python that has Pillow, which the system one does not:

    /Users/f2pgod/Documents/spyder312/bin/python tools/build_assets.py
"""

from __future__ import annotations

import argparse
import csv
import glob
import json
import multiprocessing
import os
import re
import sys
import time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(HERE, 'tools')

HOME = os.path.expanduser('~')
JSON_DATA = os.environ.get(
    'ARKHAM_JSON_DATA', os.path.join(HOME, 'Documents/arkhamdb-json-data'))

TTS = os.path.join(HOME, 'Library/Tabletop Simulator')
# Which save to read is worked out by `find_save_file`, not fixed here: the
# filename carries the mod's version and changes with every release.
SAVE_GLOB = os.path.join(TTS, 'Saves', 'Arkham SCE *.json')
SAVE_FILE = os.environ.get('ARKHAM_TTS_SAVE')
# The sprite sheets TTS itself caches when a box is opened in-game. Keyed by
# TTS's own cache-name scheme, which `sheet_filename` reproduces.
SHEET_DIR = os.environ.get('ARKHAM_TTS_SHEETS', os.path.join(TTS, 'Mods/Images'))

# The SCED campaign boxes and the sheets they name. The two caches share
# exactly one sheet name, and the TTS copy of it is a 14 KB truncation of the
# 422 KB file here -- so this directory is indexed second and wins the clash,
# which is what fixes `01693`.
BOX_DIR = os.environ.get(
    'ARKHAM_SCED_BOXES', os.path.join(HOME, 'Downloads/arkham/_boxes'))
EXTRA_SHEET_DIR = os.environ.get(
    'ARKHAM_SCED_SHEETS', os.path.join(HOME, 'Downloads/arkham/_sheets'))

SWAP_LIST = os.path.join(TOOLS, 'swap_list.json')

ASSETS = os.path.join(HERE, 'assets')
CARDS_JSON = os.path.join(ASSETS, 'cards.json')
DECKS_JSON = os.path.join(ASSETS, 'decks.json')
IMAGE_DEST = os.path.join(ASSETS, 'CardImages')
# Beside the art rather than in assets/, so it is not bundled into the app.
CROP_REPORT = os.path.join(HERE, 'build', 'crops.csv')

QUALITY = 80
# Pillow's WebP effort setting. 4 is its default; 6 costs about three times the
# time for under a percent of size on this material.
METHOD = 4

# What a run is expected to come out at. A mismatch means the upstream data
# moved, and the counts in the tests need re-checking rather than the
# assertion needing relaxing.
EXPECTED_CARDS = 5928
EXPECTED_IMAGES = 7618

# The object names TTS gives a card.
CARD_NAMES = ('Card', 'CardCustom')

# The types whose art is printed landscape. The same rule as `Card.isLandscape`
# in the app, and the reason no perceptual hash is needed here: checked against
# the 7,742 images of an older source, it agreed on 7,739 -- so it is a better
# orientation reference than the pictures were, and it needs no pictures.
LANDSCAPE_TYPES = ('investigator', 'act', 'agenda')

# Below this a crop is not a card. It catches the stale-grid case handled in
# `cell_grid`, and any future sheet whose layout has changed: 54 slivers went
# unnoticed into an earlier pipeline because nothing downstream checked.
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

# The 10 Investigator Starter Deck products, in release order. Each is a pack
# of its own holding one investigator, that deck's cards at level 0, and a set
# of upgrades that are not part of the printed deck -- see `build_decks`.
#
# Listed rather than discovered from `pack/investigator/`: a directory listing
# would silently absorb an eleventh product whose layout has not been checked,
# and every assumption `build_decks` makes was verified against these ten.
STARTER_PACKS = ('nat', 'tom', 'har', 'car', 'win',
                 'and', 'jac', 'mar', 'ste', 'mig')

# What a derived starter deck is allowed to come out at. The products are
# built to a `size:30` requirement plus signatures and a basic weakness, which
# lands at 33 today, or 35 where the investigator has extra signatures. The
# band is wide because the exact figure is not the invariant -- a deck of 12
# or 60 would mean the `xp` convention this derivation rests on has moved.
DECK_SIZE_RANGE = (30, 40)

# Promo printings upstream does not link to the card they reprint, mapped to
# that card. Every one is a standalone record carrying its own name, type and
# stats, so nothing marks it as another edition of anything -- the promo
# Roland Banks looked like a card of his own, absent from the Core Set
# Roland's editions list. arkhamdb itself treats 98004 as a printing of
# 01001; this JSON dump does not.
#
# The 14 other promotional cards are genuinely new cards with no counterpart
# elsewhere in the data, so they are not here.
PROMO_EDITIONS = {
    '98001': '02003',   # Jenny Barnes, Hour of the Huntress
    '98004': '01001',   # Roland Banks, The Dirge of Reason
    '98007': '08004',   # Norman Withers, Ire of the Void
    '98010': '05001',   # Carolyn Fern, To Fight the Black Wind
    '98013': '07005',   # Silas Marsh, The Deep Gate
    '98016': '07004',   # Dexter Drake, Blood of Baalshandor
    '98019': '11014',   # Gloria Goldberg, Dark Revelations
    '99001': '05006',   # Marie Lambeau, Promo
    '99002': '05018',   # Mystifying Song, her signature event
    '99003': '05019',   # Baron Samedi, her signature asset
}

# What has to still match for a PROMO_EDITIONS entry to be believed. Deliberately
# identity only: the promos differ from their base in flavour text, in one
# card's typo (98013) and in which signature cards they name, and those
# differences are the reason each keeps its own record.
PROMO_IDENTITY = ('name', 'subname', 'type_code')

# A card code is digits with an optional single trailing letter: 01001, 88053a.
# All 5,928 match; the letter is what distinguishes cards sharing a position.
CODE = re.compile(r'^\d+([a-z]?)$')

def log(message):
    print(message, flush=True)

def webp_name(stem):
    """The bundled filename for an image stem: `01001` -> `01001.webp`."""
    return stem + '.webp'

def image_for(images, stem, fallback):
    """The bundled filename for a stem, or for the card it reprints, or None."""
    for candidate in (stem, fallback):
        if candidate and candidate in images:
            return webp_name(candidate)
    return None

def find_save_file():
    """The newest Arkham SCE save, or None.

    The filename carries the mod's version, so it moves with every release and
    cannot be fixed in the source. The version is compared as a tuple of
    integers rather than as a string, because `4.10.0` is newer than `4.8.0`
    and sorts before it as text. A name that does not parse still sorts, just
    below every one that does, so an oddly-named save is used only when it is
    the sole candidate.
    """
    if SAVE_FILE:
        return SAVE_FILE if os.path.isfile(SAVE_FILE) else None

    def version(path):
        digits = re.findall(r'\d+', os.path.basename(path))
        return tuple(int(d) for d in digits)

    candidates = sorted(glob.glob(SAVE_GLOB), key=version)
    return candidates[-1] if candidates else None

def sheet_filename(url):
    """TTS's cache name for a URL: punctuation stripped, no extension."""
    return re.sub(r'[\/\:\-\_\.\?\=\%]', '', url)

def index_sheets():
    """Every cached sprite sheet, by the cache name TTS stored it under.

    Both caches, with EXTRA_SHEET_DIR indexed second so its copy wins the one
    name they share -- the TTS copy of that sheet is truncated.
    """
    sheets = {}
    for directory in (SHEET_DIR, EXTRA_SHEET_DIR):
        if not os.path.isdir(directory):
            continue
        for path in glob.glob(os.path.join(directory, '*')):
            sheets[os.path.splitext(os.path.basename(path))[0]] = path
    log('  {} sprite sheets cached'.format(len(sheets)))
    return sheets

def load_boxes():
    """The SCED campaign boxes, sorted by filename for a stable walk order.

    `library.json` is the mod's box manifest -- names and cover art, no cards
    -- so it is skipped rather than walked for nothing.
    """
    boxes = []
    for path in sorted(glob.glob(os.path.join(BOX_DIR, '*.json'))):
        if os.path.basename(path) == 'library.json':
            continue
        with open(path, encoding='utf8') as handle:
            boxes.append(json.load(handle))
    log('  {} campaign boxes'.format(len(boxes)))
    return boxes

def printed_number(card):
    """The number as it reads on the card, with the code's letter appended.

    `position` alone does not identify a card within its box: 379 positions
    are shared by two or more records, either because the two sides of one
    location are separate records (`05166` and `05166b`) or because a box
    prints several variants at one number (`88053a` and `88053b`). Both cases
    take the letter from the code, which is the only thing upstream uses to
    tell them apart -- so the list showed two identical rows for each.

    A string, not a number: the app only ever displays it.
    """
    match = CODE.match(card['code'])
    suffix = match.group(1) if match else ''
    return '{}{}'.format(card.get('position', 0), suffix)

def back_link_partners(cards):
    """Which cards are the two sides of one physical card, undirected.

    `back_link` points both ways in the data and cannot be read as
    front-to-back: 310 records point at a card flagged `hidden`, but 18 point
    the other way and 21 join two cards where neither is hidden. Only the
    pairing is dependable, so only the pairing is used.
    """
    partners = defaultdict(set)
    for card in cards.values():
        other = card.get('back_link')
        if other and other in cards:
            partners[card['code']].add(other)
            partners[other].add(card['code'])
    return partners

def link_variants(cards):
    """Group the variants a single box prints at one number.

    Fortune and Folly deals its encounter deck like playing cards, printing
    the same effect several times with a different suit pip: `Hunter's Hunger`
    is `88053a` (clubs 4) and `88053b` (hearts 4). The Wages of Sin has six
    `Heretic` enemies, Dim Carcosa three `Ruins of Carcosa`. Each is its own
    record with its own art, and each was showing up as a duplicate row.

    Written into `variant_of`, a separate field from `duplicate_of` and
    `alternate_of`, because this is a different relation: those two mean the
    same card in a later box, this means a different card in the same box. The
    app follows all three to build one group, but keeping them apart here
    means the distinction survives in the data.

    Cards sharing a name, a box and a position, minus any that is the far side
    of another member -- `05178a` Heretic and `05178b` Unfinished Business
    share all three but are one card's two faces, not two variants.
    """
    partners = back_link_partners(cards)

    # Runs before `resolve_reprints`, so a reprint has no `name` yet to group
    # on. That costs nothing: a reprint is the same card in a later box, which
    # is the relation `duplicate_of` already carries, never a variant.
    by_number = defaultdict(list)
    for card in cards.values():
        if card.get('duplicate_of'):
            continue
        by_number[(card['name'], card.get('pack_code'),
                   card.get('position'))].append(card)

    groups = 0
    linked = 0
    for key, candidates in sorted(by_number.items(),
                                  key=lambda item: str(item[0])):
        if len(candidates) < 2:
            continue

        codes = {card['code'] for card in candidates}
        members = [card for card in candidates
                   if not (partners[card['code']] & codes)]
        if len(members) < 2:
            continue

        # A variant is a distinct card, so it should never also claim to be a
        # reprint of one. If upstream starts saying both, that is a change in
        # what these fields mean and it should be read before being followed.
        conflicting = [card['code'] for card in members
                       if card.get('duplicate_of') or card.get('alternate_of')]
        if conflicting:
            log('  ! {} at {} #{} also carries a reprint pointer; not '
                'grouped as variants'.format(
                    ', '.join(sorted(conflicting)), key[1], key[2]))
            continue

        root = min(card['code'] for card in members)
        for card in members:
            card['variant_of'] = root
        groups += 1
        linked += len(members)

    log('  {} variants grouped into {} cards printed at one number'.format(
        linked, groups))

def load_pack_cards():
    """Every card in every pack file, keyed by code.

    A code appearing twice would mean the upstream data contradicts itself,
    so that is reported rather than silently resolved.
    """
    cards = {}
    conflicts = []
    pack_dir = os.path.join(JSON_DATA, 'pack')
    files = 0

    for root, _, names in os.walk(pack_dir):
        for name in sorted(names):
            if not name.endswith('.json'):
                continue
            files += 1
            path = os.path.join(root, name)
            with open(path, encoding='utf8') as handle:
                for card in json.load(handle):
                    code = card['code']
                    # Upstream repeats a couple of records verbatim. Only a
                    # repeat that disagrees with itself is worth reporting.
                    if code in cards and cards[code] != card:
                        conflicts.append(code)
                    cards[code] = card

    log('  {} pack files, {} cards'.format(files, len(cards)))
    if conflicts:
        log('  ! {} codes defined twice with differing data: {}'.format(
            len(conflicts), ', '.join(conflicts[:8])))
    return cards

def read_json(name):
    with open(os.path.join(JSON_DATA, name), encoding='utf8') as handle:
        return json.load(handle)

def load_reference():
    """Packs, cycles and encounter sets, so a card can name where it came from."""
    packs = read_json('packs.json')
    cycles = read_json('cycles.json')
    encounters = read_json('encounters.json')

    cycle_by_code = {c['code']: c for c in cycles}
    pack_by_code = {}
    for pack in packs:
        cycle = cycle_by_code.get(pack.get('cycle_code'), {})
        pack_by_code[pack['code']] = {
            'name': pack['name'],
            'position': pack.get('position', 0),
            'cycle_code': pack.get('cycle_code', ''),
            'cycle_name': cycle.get('name', ''),
            'cycle_position': cycle.get('position', 0),
        }

    encounter_by_code = {e['code']: e['name'] for e in encounters}
    log('  {} packs across {} cycles, {} encounter sets'.format(
        len(packs), len(cycles), len(encounters)))
    return pack_by_code, encounter_by_code

def wanted_stems(cards):
    """Every image stem the app could want, mapped to whether it is landscape.

    Run after `resolve_reprints`, so a reprint has the `type_code` its
    orientation comes from. A front's stem is the card's `code` and a back's is
    `back_link` or `<code>b`, which is what `build_records` looks images up by.
    """
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

def plan_crops(roots, wanted):
    """Build the crop list: one task per image to write.

    `roots` is the save followed by the campaign boxes; `iter_cards` walks a
    list as readily as a dict, and document order decides which printing of a
    shared code wins, so the save's player cards are never re-cut by a box.

    Deduplicated on (code, CardID, sheet), so an object the mod merely repeats
    collapses to one task while a genuinely different printing keeps its own.
    Only codes the app wants survive, which drops the mod's minicards,
    parallel investigators and extra printings.
    """
    variants = defaultdict(list)
    seen = set()
    skipped = Counter()
    found = 0

    for card in iter_cards(roots):
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
            'index': card['card_id'] % 100,
            'width': entry.get('NumWidth') or 1,
            'height': entry.get('NumHeight') or 1,
            'face': face,
            'back': entry.get('BackURL'),
            'unique_back': bool(entry.get('UniqueBack')),
            'sideways': card['sideways'],
        })
        found += 1

    log('  {} card objects in the save and boxes'.format(found))
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

def link_promo_editions(cards):
    """Point each promo in PROMO_EDITIONS at the card it is a printing of.

    Written into `alternate_of` -- the field that already means "another
    printing of this card" -- so the app's existing grouping picks these up
    with no special case. Not `duplicate_of`: `resolve_reprints` fills those
    records in from their base, which would overwrite the flavour text, the
    signature-card requirements and the one typo that make these their own
    record.

    Every entry is checked rather than trusted. A promo that has gained a
    pointer upstream, or that no longer names the same card, is skipped and
    reported: a stale line in this table should show up here rather than
    quietly group two unrelated cards together.
    """
    linked = 0
    for promo_code, base_code in sorted(PROMO_EDITIONS.items()):
        promo = cards.get(promo_code)
        base = cards.get(base_code)
        if promo is None or base is None:
            log('  ! {} -> {}: code no longer in the data'.format(
                promo_code, base_code))
            continue
        if promo.get('duplicate_of') or promo.get('alternate_of'):
            log('  ! {} now carries its own pointer upstream; drop it from '
                'PROMO_EDITIONS'.format(promo_code))
            continue
        mismatched = [key for key in PROMO_IDENTITY
                      if promo.get(key) != base.get(key)]
        if mismatched:
            log('  ! {} and {} disagree on {}; not linked'.format(
                promo_code, base_code, ', '.join(mismatched)))
            continue
        promo['alternate_of'] = base_code
        linked += 1

    log('  {} of {} promo printings linked to the card they reprint'.format(
        linked, len(PROMO_EDITIONS)))

def resolve_reprints(cards):
    """Fill a reprint in from the card it reprints.

    A `duplicate_of` record carries only a pointer, a pack and a position --
    no name, type or class -- because it is the same card in a later box. The
    app should not have to treat those fields as optional just to accommodate
    187 records it never displays, so the original's data is copied in while
    the reprint keeps its own identity and printing details.
    """
    # `variant_of` is the reprint's own business too: it names cards printed
    # at one number in one box, so inheriting a base's copy would group the
    # reprint with that base's siblings in a box the reprint is not in.
    own = ('code', 'pack_code', 'position', 'quantity', 'duplicate_of',
           'alternate_of', 'variant_of', 'illustrator', 'encounter_code',
           'encounter_position')
    filled = 0

    for card in cards.values():
        source = cards.get(card.get('duplicate_of'))
        if source is None:
            continue
        for key, value in source.items():
            if key not in own and key not in card:
                card[key] = value
        filled += 1

    log('  {} reprints filled in from the card they reprint'.format(filled))

def build_records(cards, packs, encounters, images):
    """Annotate every card and decide how its two sides are shown.

    Three things are settled here so the app never has to:

      back      - a card's reverse is either its own `<code>b` image
                  (`double_sided`) or another card entirely (`back_link`).
                  Both collapse to one filename here.

      number    - the printed number, which needs the code's letter to be
                  unique within a box. See `printed_number`.

      sort      - cycle, then pack, then position within the pack.

    `images` is the set of stems `crop_images` managed to write. The two image
    fields name the WebP rather than the stem, so the app never has to add an
    extension or stat the filesystem.

    Every record is listable. Reprints and the far halves of `back_link`
    pairs were once filtered out of the list, on the grounds that they
    double a card up; they are their own printing with their own art and
    their own code, so they get their own row. The counts below are kept
    because a sudden change in either is a sign the upstream data moved.
    """
    records = []
    counts = Counter()
    missing_backs = []

    for code, card in cards.items():
        pack = packs.get(card.get('pack_code'), {})

        record = dict(card)
        record['pack_name'] = pack.get('name', card.get('pack_code', ''))
        record['cycle_code'] = pack.get('cycle_code', '')
        record['cycle_name'] = pack.get('cycle_name', '')
        if card.get('encounter_code'):
            record['encounter_name'] = encounters.get(
                card['encounter_code'], card['encounter_code'])
        record['printed_number'] = printed_number(card)
        record['sort_key'] = [
            pack.get('cycle_position', 99),
            pack.get('position', 99),
            card.get('position', 0),
        ]

        if card.get('hidden'):
            counts['flagged hidden upstream'] += 1
        if card.get('duplicate_of'):
            counts['reprint of another card'] += 1

        # A reprint with no picture of its own borrows the one belonging to the
        # card it reprints, which is the same card in an earlier box. The art
        # source is the TTS mod, which stocks each card once and does not carry
        # the later printing's code, so without this 52 cards -- the Revised Core
        # Set investigators and the starter decks' reprints among them -- show a
        # placeholder while their Core Set twin, the identical card, has a
        # picture.
        reprint_of = card.get('duplicate_of') or card.get('alternate_of')

        front = image_for(images, code, reprint_of)
        record['front_image'] = front
        if front is None:
            counts['no front image'] += 1

        back_code = None
        if card.get('back_link'):
            back_code = card['back_link']
        elif card.get('double_sided'):
            back_code = code + 'b'

        back = image_for(
            images, back_code,
            (reprint_of + 'b') if reprint_of else None) if back_code else None
        record['back_image'] = back
        record['back_code'] = back_code
        if back_code and back is None:
            counts['no back image'] += 1
            missing_backs.append(record)

        records.append(record)

    records.sort(key=lambda r: (r['sort_key'], r['code']))

    log('  {} records'.format(len(records)))
    for reason, count in sorted(counts.items()):
        log('    {:<16} {}'.format(reason, count))

    if len(records) != EXPECTED_CARDS:
        log('  ! expected {} cards, built {}. If the upstream data changed, '
            'update EXPECTED_CARDS here and the matching counts in the '
            'tests.'.format(EXPECTED_CARDS, len(records)))

    # Named rather than just counted, because the count alone cannot tell a
    # card the game prints one-sided from one whose back the extraction simply
    # did not reach. 98004 is the latter: the data says it has a back, and the
    # app drew no flip button with no way to tell that was wrong. These fall
    # back to the card's text on the detail screen.
    if missing_backs:
        log('  {} cards want a back image the extraction does not have:'.format(
            len(missing_backs)))
        for record in sorted(missing_backs, key=lambda r: r['code'])[:12]:
            log('    {:<8} {:<32} {}'.format(
                record['code'], record['name'][:32], record['pack_name']))
    return records

def build_decks(records):
    """Derive the 10 Investigator Starter Decks from their pack files.

    Each product is a pack holding the investigator, the 30-odd cards of the
    printed deck, and a further 18-26 cards of upgrades to buy with experience
    later. Nothing marks which is which except `xp`: the printed deck is every
    non-investigator card in the pack at level 0, and an upgrade is anything
    above it. That is the whole rule, and it is worth stating because it is
    inferred rather than declared -- upstream has no "starter deck" field.

    Two forms of level 0 both count. Most cards say `xp: 0`; the signature
    cards and the basic weakness omit `xp` entirely, because a card that
    cannot be bought has no level to state. Reading a missing `xp` as anything
    but zero drops exactly the cards that define the investigator.

    Runs after `resolve_reprints`, so the reprints these packs are full of --
    `60108` is the Core Set's Physical Training, and carries nothing but a
    pointer upstream -- have a name and a type by the time they are counted.

    Quantities come from `quantity`, which is how many copies the box
    contains. For a starter deck that is also how many the deck runs, so no
    deck-building rule has to be applied here.
    """
    by_pack = defaultdict(list)
    for record in records:
        by_pack[record.get('pack_code')].append(record)

    decks = []
    for pack_code in STARTER_PACKS:
        pack = by_pack.get(pack_code)
        if not pack:
            log('  ! {}: pack not in the data; no deck built'.format(pack_code))
            continue

        investigators = [c for c in pack if c.get('type_code') == 'investigator']
        # One investigator per product is the premise of the whole derivation:
        # a second would mean these slots belong to two decks and there is no
        # way to tell which card goes with which.
        if len(investigators) != 1:
            log('  ! {}: {} investigators, expected 1; no deck built'.format(
                pack_code, len(investigators)))
            continue
        investigator = investigators[0]

        slots = {}
        for card in pack:
            if card.get('type_code') == 'investigator':
                continue
            if (card.get('xp') or 0) != 0:
                continue
            slots[card['code']] = card.get('quantity', 1)

        size = sum(slots.values())
        low, high = DECK_SIZE_RANGE
        if not low <= size <= high:
            log('  ! {} derives {} cards, outside {}-{}; no deck built'.format(
                pack_code, size, low, high))
            continue

        decks.append({
            'pack_code': pack_code,
            # The product is named after its investigator, so this is both the
            # deck's name and the box's.
            'name': investigator['name'],
            'investigator_code': investigator['code'],
            'slots': slots,
        })
        log('    {:<4} {:<20} {} cards'.format(
            pack_code, investigator['name'][:20], size))

    log('  {} of {} starter decks built'.format(len(decks), len(STARTER_PACKS)))
    return decks

def crop_sheet(job):
    """Cut every card wanted from one sprite sheet, writing each as WebP.

    One sheet per job rather than one card, because a sheet is up to 7500x7350
    and decoding it once for each of the 40 cards on it dominates the run.

    Returns a (stem, status) pair per task, `'ok'` or the reason it failed. A
    sheet that will not open fails all of its cards rather than raising, so one
    truncated file in the cache does not end the build.
    """
    path, tasks = job
    from PIL import Image

    # Sprite sheets are legitimately huge (7500x7350 and up).
    Image.MAX_IMAGE_PIXELS = None

    try:
        with Image.open(path) as sheet:
            sheet.load()
            results = []
            for task in tasks:
                cell = crop(sheet, task)
                if not is_card_shaped(cell.size):
                    results.append((task['stem'],
                                    'implausible crop {}x{}'.format(*cell.size)))
                    continue
                # Card art has no alpha, and RGB avoids WebP writing an alpha
                # channel for images whose mode is merely capable of one.
                cell.convert('RGB').save(
                    os.path.join(IMAGE_DEST, webp_name(task['stem'])),
                    'WEBP', quality=QUALITY, method=METHOD)
                results.append((task['stem'], 'ok'))
            return results
    except Exception as error:  # noqa: BLE001 - reported, not swallowed
        reason = '{}: {}'.format(type(error).__name__, error)[:80]
        return [(task['stem'], reason) for task in tasks]

def crop_images(tasks, sheets, force):
    """Crop every task that is not already up to date. Returns its status per stem.

    Incremental on the sheet's own timestamp: a WebP newer than the sheet it
    came from is left alone, so a run that only needs one changed box does not
    re-encode all of them.
    """
    os.makedirs(IMAGE_DEST, exist_ok=True)
    existing = set(os.listdir(IMAGE_DEST))

    status = {}
    by_sheet = defaultdict(list)
    missing = 0
    for task in tasks:
        path = sheets.get(sheet_filename(task['url']))
        if path is None:
            status[task['stem']] = 'sheet not cached'
            missing += 1
            continue

        name = webp_name(task['stem'])
        destination = os.path.join(IMAGE_DEST, name)
        if (not force and name in existing
                and os.path.getmtime(destination) >= os.path.getmtime(path)):
            status[task['stem']] = 'ok'
            continue
        by_sheet[path].append(task)

    pending = sum(len(group) for group in by_sheet.values())
    log('  {} to crop from {} sheets, {} up to date, {} sheets not cached'.format(
        pending, len(by_sheet), len(tasks) - pending - missing, missing))

    if by_sheet:
        jobs = sorted(by_sheet.items())
        started = time.monotonic()
        done = 0
        with multiprocessing.Pool() as pool:
            for number, results in enumerate(
                    pool.imap_unordered(crop_sheet, jobs), start=1):
                status.update(results)
                done += len(results)
                if number % 100 == 0 or number == len(jobs):
                    log('    sheet {}/{}  {} cards  {:.0f}s'.format(
                        number, len(jobs), done, time.monotonic() - started))

    return status

def write_crop_report(status, tasks):
    """Every crop and how it went, for working out why one card looks wrong.

    Counting failures is not enough to tell a card the mod does not carry from
    one whose cached sheet arrived truncated, and only the second is worth
    acting on.
    """
    os.makedirs(os.path.dirname(CROP_REPORT), exist_ok=True)
    fields = ['stem', 'code', 'cell', 'grid', 'sheet', 'status']
    with open(CROP_REPORT, 'w', newline='', encoding='utf8') as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for task in sorted(tasks, key=lambda task: task['stem']):
            writer.writerow({
                'stem': task['stem'],
                'code': task['code'],
                'cell': task['index'],
                'grid': '{}x{}'.format(task['width'], task['height']),
                'sheet': task['url'],
                'status': status.get(task['stem'], 'not attempted'),
            })

def prune_images(records):
    """Delete any bundled image no card record names.

    The asset directory is declared wholesale in pubspec, so an image left over
    from an earlier build -- one whose card has since lost its art, or the whole
    encounter side of a previous pipeline -- would ship with nothing showing it.
    """
    referenced = {
        record[key] for record in records
        for key in ('front_image', 'back_image') if record[key]
    }
    stale = set(os.listdir(IMAGE_DEST)) - referenced
    for name in stale:
        os.remove(os.path.join(IMAGE_DEST, name))

    bundled = os.listdir(IMAGE_DEST)
    total = sum(os.path.getsize(os.path.join(IMAGE_DEST, name))
                for name in bundled)
    log('  {} images, {:.2f} GB, {} stale removed'.format(
        len(bundled), total / 1e9, len(stale)))

    if len(bundled) != EXPECTED_IMAGES:
        log('  ! expected {} images, bundled {}. If the upstream data '
            'changed, update EXPECTED_IMAGES here, in publish_assets.sh, in '
            'the workflow and in the tests together.'.format(
                EXPECTED_IMAGES, len(bundled)))
    return len(bundled)

def check_images_present(records):
    """Every image a card names must be on disk.

    The app shows a placeholder for a card with no art, but a card naming art
    that is not there fails silently at decode time instead.
    """
    missing = sorted({
        record[key] for record in records for key in ('front_image', 'back_image')
        if record[key]
        and not os.path.isfile(os.path.join(IMAGE_DEST, record[key]))
    })
    if missing:
        log('  ! {} images named by cards.json are not bundled: {}'.format(
            len(missing), missing[:10]))
        return False
    return True

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--force', action='store_true', help='re-crop images that exist')
    parser.add_argument(
        '--skip-images', action='store_true',
        help='rebuild the JSON only, keeping the art already bundled')
    arguments = parser.parse_args()

    if not os.path.isdir(JSON_DATA):
        log('Missing source: {}'.format(JSON_DATA))
        return 1
    if not os.path.isdir(SHEET_DIR):
        log('Missing source: {}'.format(SHEET_DIR))
        return 1
    if not arguments.skip_images:
        for source in (BOX_DIR, EXTRA_SHEET_DIR):
            if not os.path.isdir(source):
                log('Missing source: {}'.format(source))
                return 1

    save = find_save_file()
    if save is None:
        log('No Arkham SCE save found at {}'.format(SAVE_GLOB))
        log('Set ARKHAM_TTS_SAVE to name one explicitly.')
        return 1

    os.makedirs(ASSETS, exist_ok=True)

    log('Reading card data')
    cards = load_pack_cards()
    link_promo_editions(cards)
    link_variants(cards)
    resolve_reprints(cards)
    packs, encounters = load_reference()

    if arguments.skip_images:
        # The bundle stands in for a crop that has not been run, so the JSON
        # keeps naming exactly the art already there.
        log('Skipping the crop; taking the images already bundled')
        images = {os.path.splitext(name)[0]
                  for name in os.listdir(IMAGE_DEST)} if os.path.isdir(
                      IMAGE_DEST) else set()
        log('  {} images already bundled'.format(len(images)))
    else:
        log('Reading Tabletop Simulator')
        log('  save: {}'.format(os.path.basename(save)))
        with open(save, encoding='utf8') as handle:
            save_data = json.load(handle)
        boxes = load_boxes()
        sheets = index_sheets()

        log('Planning the crop')
        # The save first: 167 codes appear in a box too, and document order
        # decides which printing wins, so this keeps every player-card crop
        # exactly what the save-only pipeline produced.
        tasks = plan_crops([save_data] + boxes, wanted_stems(cards))

        log('Cropping')
        status = crop_images(tasks, sheets, arguments.force)
        write_crop_report(status, tasks)
        images = {stem for stem, state in status.items() if state == 'ok'}

        failed = sorted((stem, state) for stem, state in status.items()
                        if state != 'ok')
        log('  {} cropped, {} failed, report at {}'.format(
            len(images), len(failed), CROP_REPORT))
        # Named, not just counted: the count alone cannot tell a card the mod
        # does not carry from one whose cached sheet arrived truncated, and only
        # the second is worth acting on. `01693` is the standing example -- its
        # sheet in the TTS cache is 14 KB against the 422 KB it should be, so it
        # will not open at all.
        for stem, state in failed[:20]:
            log('    {:<9} {}'.format(stem, state[:60]))

    log('Building records')
    records = build_records(cards, packs, encounters, images)

    log('Building starter decks')
    decks = build_decks(records)

    if not arguments.skip_images:
        log('Pruning the bundle')
        prune_images(records)

    if not check_images_present(records):
        return 1

    with open(CARDS_JSON, 'w', encoding='utf8') as handle:
        json.dump(records, handle, ensure_ascii=False, separators=(',', ':'))

    with open(DECKS_JSON, 'w', encoding='utf8') as handle:
        json.dump(decks, handle, ensure_ascii=False, indent=1, sort_keys=True)

    log('\nWrote {} ({:.1f} MB)'.format(
        CARDS_JSON, os.path.getsize(CARDS_JSON) / 1e6))
    log('Wrote {} ({} decks)'.format(DECKS_JSON, len(decks)))
    return 0

if __name__ == '__main__':
    sys.exit(main())
