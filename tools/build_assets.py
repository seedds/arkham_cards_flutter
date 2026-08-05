#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the app's bundled assets from the two upstream sources.

Reads:
  arkhamdb-json-data/  - 159 pack files, plus packs/cycles/factions/types
  arkham-tts/          - one PNG per card code, from tools/extract_tts_images.py

Writes:
  assets/cards.json     - every card, merged and annotated
  assets/decks.json     - the 10 Investigator Starter Decks
  assets/CardImages/    - one WebP per referenced code

Neither source is in this repo and neither is version-pinned. `docs/DATA.md` is
the reference for their shape; most of what looks over-complicated below is
explained there. The guiding rule: **settle a data quirk here, so the Dart
model does not carry a special case for it.**

The images are transcoded rather than copied, because Flutter's engine cannot
decode AVIF and the one package that can offers no decode-time downsampling --
which is the mechanism the whole memory budget rests on. Each card records the
WebP filename, so nothing at runtime has to guess an extension or stat the
filesystem.

Run with the Python that has Pillow, which the system one does not:

    /Users/f2pgod/Documents/spyder312/bin/python tools/extract_tts_images.py
    /Users/f2pgod/Documents/spyder312/bin/python tools/build_assets.py
"""

from __future__ import annotations

import argparse
import json
import multiprocessing
import os
import re
import sys
import time
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HOME = os.path.expanduser('~')
JSON_DATA = os.environ.get(
    'ARKHAM_JSON_DATA', os.path.join(HOME, 'Documents/arkhamdb-json-data'))
IMAGE_SRC = os.environ.get(
    'ARKHAM_IMAGE_SRC', os.path.join(HOME, 'Downloads/arkham-tts'))

ASSETS = os.path.join(HERE, 'assets')
CARDS_JSON = os.path.join(ASSETS, 'cards.json')
DECKS_JSON = os.path.join(ASSETS, 'decks.json')
IMAGE_DEST = os.path.join(ASSETS, 'CardImages')

QUALITY = 80
# Pillow's WebP effort setting. 4 is its default; 6 costs about three times the
# time for under a percent of size on this material.
METHOD = 4

# What a run is expected to come out at. A mismatch means the upstream data
# moved, and the counts in the tests need re-checking rather than the
# assertion needing relaxing.
EXPECTED_CARDS = 5928
EXPECTED_IMAGES = 7617

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

# extract_tts_images.py writes PNG and nothing else: it crops from sprite
# sheets, so a lossy intermediate would cost a generation for no reason.
EXTENSIONS = ('.png',)

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

def webp_name(filename):
    """The bundled name for an extracted image: `01001.png` -> `01001.webp`."""
    return os.path.splitext(filename)[0] + '.webp'

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

def index_images():
    """Map each card code to its best available image filename."""
    best = {}
    for name in os.listdir(IMAGE_SRC):
        stem, extension = os.path.splitext(name)
        extension = extension.lower()
        if extension not in EXTENSIONS:
            continue
        current = best.get(stem)
        if current is None or rank(extension) < rank(os.path.splitext(current)[1]):
            best[stem] = name
    log('  {} images on disk'.format(len(best)))
    return best

def rank(extension):
    return EXTENSIONS.index(extension.lower())

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

    The two image fields name the WebP that `transcode_images` writes, not the
    PNG the extraction leaves, so the app never has to map one to the other.

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

        front = images.get(code) or images.get(reprint_of)
        record['front_image'] = webp_name(front) if front else None
        if front is None:
            counts['no front image'] += 1

        back_code = None
        if card.get('back_link'):
            back_code = card['back_link']
        elif card.get('double_sided'):
            back_code = code + 'b'

        back = images.get(back_code) if back_code else None
        if back is None and back_code and reprint_of:
            back = images.get(reprint_of + 'b')
        record['back_image'] = webp_name(back) if back else None
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

def transcode(job):
    """Re-encode one upstream image as WebP. Returns (name, bytes) or (name, None)."""
    source, destination = job
    try:
        from PIL import Image

        with Image.open(source) as image:
            image.load()
            # Card art has no alpha, and RGB avoids WebP writing an alpha
            # channel for images whose mode is merely capable of one.
            image.convert('RGB').save(
                destination, 'WEBP', quality=QUALITY, method=METHOD)
        return os.path.basename(source), os.path.getsize(destination)
    except Exception as error:  # noqa: BLE001 - reported, not swallowed
        print('  {}: {}: {}'.format(
            os.path.basename(source), type(error).__name__, error),
            file=sys.stderr)
        return os.path.basename(source), None

def transcode_images(records, images, force):
    """Re-encode as WebP only the images some card actually points at.

    The extraction can write images no card record points at -- cards the TTS
    mod carries and this data dump does not -- which would otherwise be dead
    weight in the bundle.
    """
    # Every image index entry is keyed by stem, so no two source files can
    # collapse onto one WebP name.
    source_by_name = {webp_name(name): name for name in images.values()}

    wanted = set()
    for record in records:
        for key in ('front_image', 'back_image'):
            if record[key]:
                wanted.add(record[key])

    os.makedirs(IMAGE_DEST, exist_ok=True)
    existing = set(os.listdir(IMAGE_DEST))

    # Images no longer referenced would otherwise linger and be shipped, since
    # the asset directory is declared wholesale in pubspec.
    for stale in existing - wanted:
        os.remove(os.path.join(IMAGE_DEST, stale))

    jobs = []
    skipped = 0
    for name in sorted(wanted):
        source = os.path.join(IMAGE_SRC, source_by_name[name])
        destination = os.path.join(IMAGE_DEST, name)
        # Transcoding all of them takes a couple of minutes, which is long
        # enough to be worth not repeating for the sake of one changed card.
        if (not force and name in existing
                and os.path.getmtime(destination) >= os.path.getmtime(source)):
            skipped += 1
            continue
        jobs.append((source, destination))

    log('  {} referenced, {} removed, {} to transcode, {} up to date'.format(
        len(wanted), len(existing - wanted), len(jobs), skipped))

    failed = []
    if jobs:
        started = time.monotonic()
        with multiprocessing.Pool() as pool:
            for index, (name, size) in enumerate(
                    pool.imap_unordered(transcode, jobs, chunksize=16), start=1):
                if size is None:
                    failed.append(name)
                if index % 500 == 0 or index == len(jobs):
                    log('    {}/{}  {:.0f}s'.format(
                        index, len(jobs), time.monotonic() - started))

    if failed:
        log('  ! {} images failed to transcode: {}'.format(
            len(failed), failed[:10]))
        return None

    bundled = os.listdir(IMAGE_DEST)
    total = sum(os.path.getsize(os.path.join(IMAGE_DEST, name))
                for name in bundled)
    log('  {} images, {:.2f} GB'.format(len(bundled), total / 1e9))

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
        '--force', action='store_true', help='re-transcode images that exist')
    parser.add_argument(
        '--skip-images', action='store_true', help='rebuild the JSON only')
    arguments = parser.parse_args()

    for path in (JSON_DATA, IMAGE_SRC):
        if not os.path.isdir(path):
            log('Missing source: {}'.format(path))
            return 1

    os.makedirs(ASSETS, exist_ok=True)

    log('Reading card data')
    cards = load_pack_cards()
    link_promo_editions(cards)
    link_variants(cards)
    resolve_reprints(cards)
    packs, encounters = load_reference()

    log('Indexing images')
    images = index_images()

    log('Building records')
    records = build_records(cards, packs, encounters, images)

    log('Building starter decks')
    decks = build_decks(records)

    if arguments.skip_images:
        log('Skipping images')
    else:
        log('Transcoding images')
        if transcode_images(records, images, arguments.force) is None:
            return 1

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
