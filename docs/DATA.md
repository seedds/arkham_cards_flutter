# The upstream data

Most of this project's complexity is not in the app — it is in the shape of the
two upstream sources. This document is the reference for that shape. If a piece
of code looks over-complicated, the reason is probably on this page.

Neither source is in this repo, and neither is version-pinned.

| Source | Provides |
| --- | --- |
| `~/Documents/arkhamdb-json-data` | 5,928 cards in 159 pack files, plus pack, cycle, faction, type and encounter-set names |
| `~/Library/Tabletop Simulator` + the SCED boxes | the sprite sheets the card art is cut out of |

`tools/extract_tts_images.py` crops the art; `tools/build_assets.py` reads the
card data and the crops and writes `assets/`. The guiding rule: **settle a data
quirk in the build script, so the Dart model does not carry a special case for
it.**

The images are transcoded, not copied: Flutter cannot decode the AVIF the
sheets sometimes arrive as, so every crop is re-encoded as WebP and each card
records the WebP filename.

### Why the art comes from Tabletop Simulator

It used to be a loose copy of `arkhamhorror.app`'s card directory at
`~/Documents/arkham-horror/…`. That tree had no remote, no tag and no way to
reproduce it — 2 GB recoverable from nowhere if the directory were lost — and
the script that populated it read the very tree it was replacing to decide
what to write.

The [SCED](https://github.com/argonui/SCED) Tabletop Simulator mod carries the
same art as sprite sheets, published per campaign box, and every sheet is
already in the local cache. The trade is coverage: see
[What the extraction cannot reach](#what-the-extraction-cannot-reach).

## The card set, by the numbers

5,928 records, every one with a distinct code and a row of its own. That
includes the 187 reprints and the 335 flagged `hidden`: each is a separate
card with its own box, number and art.

| Type | Count |
| --- | --- |
| location | 1,257 |
| asset | 1,256 |
| treachery | 753 |
| enemy | 685 |
| event | 571 |
| act | 374 |
| agenda | 324 |
| story | 227 |
| skill | 186 |
| scenario | 149 |
| investigator | 111 |
| key | 22 |
| enemy_location | 13 |

## Eight quirks worth knowing

### 1. A card can have two sides, in two different ways

1,893 cards are `double_sided`: the back is the same card, and its art is
`<code>b`. A further 350 use `back_link`, where the back is a **separate card
record with its own name, stats and text**.

`build_assets.py` collapses both into one `back_image` field, so the app asks
`card.hasBack` and does not care which form it was. Where the text of the back
matters, `CardDatabase.back` resolves the `back_link` record.

335 cards are flagged `hidden`, and it is tempting to read that as "the far
half of a pair". It is not quite that. Test it properly — is this code some
other record's `back_code`? — and the 335 split:

| | Count |
| --- | --- |
| Pointed at as another record's back | 307 |
| Pointed at by nothing | 28 |

The 28 include 6 promo investigators (`98001` Jenny Barnes, `98004` Roland
Banks, `98007`, `98013`, `98016`, `98019`), both halves of `10016` Hank
Samson, and `01000` Random Basic Weakness. `hidden` is upstream's word for
something broader than a card back, nothing in the app reads it, and every
flagged card is listed like any other.

Those 6 promo investigators are also the clearest case of quirk 3 below:
`hidden` is the *only* thing marking them as anything other than a brand-new
card, and it is not a pointer, so it cannot say which card they reprint.

**Trap:** the two sides of a `back_link` pair are *different cards*. Never fall
back to one side's art to fill in for the other — that captions one card's
picture with another card's name. This has already happened once.

A *reprint* is the opposite case and the fallback there is sound: `duplicate_of`
and `alternate_of` mean the same card in another box, so borrowing that card's
picture shows the right card. Do not conflate the two relations.

### 2. Front and back are independently optional

`05288a` (Dark Knowledge v. II) has a back image and **no front image**. A card
having art at all is not implied by it having a back, or the reverse.

- 124 cards have no front art
- 54 cards have no art on either side

The detail screen shows the card's text for a side with no picture; a row, which
has no space for text, shows `CardPlaceholder`. That widget sheds its contents as
it shrinks, so a 28pt row thumbnail is a bare tinted rectangle — the icon and
name it draws at full size overflow a box that small, and the row prints the name
beside it anyway. Only `09600a` Café Luna and `10593a` Muddy Fen have neither art
nor text, so they are the only two cards whose *detail* screen shows it.

### 3. 169 cards were printed more than once

Group sizes: 135 cards have 2 printings, 29 have 3, 3 have 4, and 2 have 5. The
art usually differs between them, which is the reason the detail screen shows a
row per printing — though a reprint the TTS mod has no object for borrows the
original's picture, so 34 groups now show one image across several rows.

Two pointer fields link them:

- `duplicate_of` (187 cards) — a reprint: Revised Core, Core 2026, an
  investigator starter deck
- `alternate_of` (28 cards) — the 13 parallel investigators, 5 Revised Core
  cards that also carry `duplicate_of`, and the 10 promos below

`CardDatabase.printings` follows both back to the original. Two edge cases it
must survive, both real in the current data:

- **Five cards carry both pointers** (`01501`–`01505`), naming the same
  original either way.
- **One pointer chains** — it names a card that is itself a reprint — so
  following must repeat until reaching a card with no pointer.

#### 10 promo printings point at nothing

Upstream gives these a **full standalone record** — own name, type, stats, text
— and no pointer of any kind, so nothing in the data says they are another
edition of a card that already exists. Compare them field by field against the
rest of the set and they match one card exactly:

| Promo | Is a printing of | Differs only in |
| --- | --- | --- |
| `98001` Jenny Barnes | `02003` | which signature cards it names |
| `98004` Roland Banks | `01001` | flavour text |
| `98007` Norman Withers | `08004` | `errata_date` |
| `98010` Carolyn Fern | `05001` | `tags` |
| `98013` Silas Marsh | `07005` | a one-character typo in `text` |
| `98016` Dexter Drake | `07004` | nothing |
| `98019` Gloria Goldberg | `11014` | nothing |
| `99001` Marie Lambeau | `05006` | which signature cards it names |
| `99002` Mystifying Song | `05018` | `restrictions` (names `99001`) |
| `99003` Baron Samedi | `05019` | `restrictions` (names `99001`) |

`build_assets.py` writes the missing `alternate_of` from a hardcoded table, so
`printings` groups them with no special case in the app. **`alternate_of`, not
`duplicate_of`**: reprint records get filled in from their base, which would
overwrite exactly the flavour text, typo and signature-card pointers that give
each promo a record of its own.

The table is verified rather than trusted — each entry is skipped and logged if
the code is gone, has gained a pointer upstream, or no longer agrees with its
base on `name`, `subname` and `type_code`.

The **other 14 promotional cards are genuinely new** (Green Man Medallion,
Mysteries Remain, Sacrificial Beast…) with no counterpart, and stay ungrouped.
Do not widen the table by name-matching alone: 139 signature clusters in the
data share a name and every stat while being separate cards — the eight
identical `Heretic` enemies in The Wages of Sin, six `Sickening Reality` story
cards, four `Legs of Atlach-Nacha`.

### 4. Reprint records are nearly empty

A `duplicate_of` record has no `name`, no `type_code` and no `faction_code` —
just a code, a pack, a position and the pointer. It is the same card in a
later box.

Rather than make those fields nullable throughout the Dart model for the sake
of 187 records the list never shows, `build_assets.py` fills each reprint in
from the card it reprints, preserving its own identity fields (code, pack,
position, illustrator).

**If you make `Card.name` nullable, this is why you did not need to.**

### 5. Numeric fields are not always numbers

Upstream uses negative numbers as an enum inside otherwise numeric fields.
`CardValue` decodes them:

| JSON | Means | Count in data |
| --- | --- | --- |
| `-2` | X | 77 |
| `-3` | `*` | 20 |
| `-4` | `?` | 2 |
| `null` | printed dash | — |
| `-11`, `-14` | **undocumented** | 4 |

The last row is a live trap. Four location cards (`87009`, `87018`, `87027`,
`72028`) carry shroud values of `-11` and `-14` which are in no schema and
which `CardValue` currently decodes as the literal numbers. Nothing displays
them today — the detail screen is image-only, so `CardValue.display` has no
callers — but **any view that starts showing stats will print "-11"** unless
these are handled first.

### 6. `position` does not identify a card within its box

379 positions are shared by two or more records, covering 816 cards. Two
different things cause it:

| Cause | Example | Groups |
| --- | --- | --- |
| The two sides of one card are separate records | `05166` / `05166b` Hangman's Brook | 321 |
| One box prints several variants at one number | `88053a` / `88053b` Hunter's Hunger | 51 |

Both take the distinguishing letter from the *code*, not from `position`, so
`build_assets.py` writes a **`printed_number`** — `position` plus that letter,
as a string: `"53a"`, `"166b"`, `"104"`. The list shows this instead of
`position`, which took 356 byte-identical rows down to none.

**The variants are not reprints.** Fortune and Folly deals its encounter deck
like playing cards, printing one effect several times with a different suit
pip; The Wages of Sin has six `Heretic` enemies; Dim Carcosa three
`Ruins of Carcosa`. These are *different cards in the same box*, where
`duplicate_of` and `alternate_of` mean *the same card in a later box*. So
`link_variants` writes a third field, **`variant_of`**, and the two relations
stay distinct in the data. No card carries both, and the build script reports
rather than links if that ever changes.

`CardDatabase.groupPrintings` follows all three pointers into one group,
because "what else is this card" is one question to a reader.

**The rule has to exclude `back_link` partners.** A shared name, box and
position can equally mean the two faces of one card. All twelve of
`05178a`–`05178l` sit at position 178 in The Wages of Sin: six `Heretic`
fronts, each linked to an `Unfinished Business` back. Grouping on name and
position alone merges the two into a twelve-card group.

That exclusion cannot read `back_link` as a direction. It points both ways:

| | Count |
| --- | --- |
| Source → `hidden` target | 310 |
| `hidden` source → target | 18 |
| Neither side `hidden` | 21 |

Only the *pairing* is dependable, so `back_link_partners` builds it undirected
and drops any candidate that is another candidate's partner.

Two results are worth expecting rather than mistaking for bugs. The largest
group is `Replicating Aberration`, nine variants at `blbe` #10, **none of
which has bundled art** — its version list is nine placeholder rows, which is
correct. And `10016a`/`10016b` Hank Samson are two investigators with
genuinely different stat lines (4/6 against 6/4 health and sanity), so that
group renders landscape art.

### 7. A starter deck pack is not a starter deck

The ten Investigator Starter Deck products live in `pack/investigator/` — one
file each: `nat`, `tom`, `har`, `car`, `win`, `and`, `jac`, `mar`, `ste`,
`mig`. Each holds 31–34 records, and **the printed deck is only some of them**.
The rest are upgrade cards boxed with the product to buy with experience later.

Nothing in the data marks the difference. There is no "starter deck" field, no
tag, no flag. The only thing separating the two is `xp`:

| | Records | Copies |
| --- | --- | --- |
| The investigator | 1 | — |
| The printed deck (level 0) | 17–21 | 33, or 35 for `and` and `ste` |
| Upgrades (level 1+) | 12–14 | 18–26 |

**Two forms of level 0 both count.** Most cards say `xp: 0`. The signature
cards and the basic weakness omit `xp` entirely, because a card you cannot buy
has no level to state. Reading a missing `xp` as anything other than zero
drops exactly the cards that define the investigator — Nathaniel Cho loses
Randall Cho, Tommy Malloy and Self-Destructive, and the deck comes out at 30.

The investigator's `deck_requirements` says `size:30` plus its signatures plus
a random basic weakness, which is where 33 comes from. André Patel and Stella
Clark have four and three signature cards respectively, hence 35.

These packs are also full of reprints: `60108` is the Core Set's Physical
Training and carries nothing but `duplicate_of: 01017` upstream. `build_decks`
runs after `resolve_reprints` so they arrive with a name and a type.

**Verified against a second source.** zzorba/ArkhamCards hand-curates starter
decks for five of these ten investigators in `src/data/deck/starterDecks.ts`.
Following reprint codes back to the card they reprint, the derivation matches
all five exactly. `build_decks` additionally refuses to emit a deck outside
30–40 cards, so a change in the `xp` convention fails the build.

**Every investigator does not have one.** That app's file holds 42 decks, of
which only those five are these products; the other 37 are the suggested
decklists printed on box inserts, covering the investigators of cycles 01–07
(Core through Innsmouth). Roland Banks is one of them — he has an insert
decklist, not a Starter Deck product.

Those 37 are not included here, and the reason is not that they would not
work: all 37 resolve against the bundle and every card in them has bundled
art. They are excluded because they are hand-curated by that project rather
than derived from anything, and `zzorba/ArkhamCards` carries no LICENSE file.
Using it to *check* a derivation is a different thing from vendoring its data.

Two further consequences if that is ever revisited. The roster would still be
short by 38 of the 85 original investigators — everything from Edge of the
Earth on (`eoe`, `tsk`, `fhv`, `tdc`), the five Core Set (2026) ones, the four
campaign-only TCU investigators, `Body of a Yithian` and `Subject 5U-21`. And
the 37 run 32–45 cards, so the tidy 33 that `DECK_SIZE_RANGE` guards stops
describing the decks tab.

### 8. Two records are defined twice

`11536` and `11552` each appear twice in `tdcc.json`, byte-identical. The build
script only warns when a repeated code carries *differing* data, so these are
silent. Do not "fix" the loader to warn on all repeats; it will just be noise.

## Images

The art is cut out of Tabletop Simulator sprite sheets by
`tools/extract_tts_images.py`, which writes one PNG per card code into a
staging directory. `build_assets.py` transcodes those to WebP and records the
`.webp` filename on each card, so the app never guesses an extension or stats
the filesystem.

7,617 images end up bundled, at 1.19 GB.

### How TTS stores a card

A card object's `CardID` encodes two things:

| | |
| --- | --- |
| `str(CardID)[:-2]` | a key into the object's `CustomDeck`, naming the sheet |
| `CardID % 100` | the cell, in a `NumWidth` x `NumHeight` grid, row-major |

The ArkhamDB code is in `GMNotes`, as JSON under `id`. 123 card objects have no
code there — the Exploration Map, Open Sky, the Fortune and Folly playing cards
— and are skipped.

**A card in a bag has a stale `CustomDeck`.** TTS does not refresh it, so the
entry has to be looked up in the nearest enclosing deck as a fallback. This is
what the mod's own `AllEncounterCardsBag` script does.

### Three traps in the sprite sheets

**The declared grid can be a lie.** A sheet holding a single 750x1050 card can
declare `3x2` or `7x2`, left over from an edit upstream that split a sheet
without updating `NumWidth`/`NumHeight`. Slicing by it yields a 250x525 sliver
of one card. 54 of those shipped unnoticed in the first attempt, because nothing
downstream looked at a picture's shape. `cell_grid` overrides a grid that would
produce a non-card-shaped cell, and `test/card_images_test.dart` pins the
result.

The test has to be on the **cell**, not the sheet: a 4x2 sheet of 750x1050
cards is 3000x2100, whose 1.43 is as card-shaped as a card. Testing the sheet
wrote 684 whole sprite sheets as single cards.

**`SidewaysCard` is not enough to get orientation right.** 26 crops came out a
quarter-turn round with it alone. The card's `type_code` is the better
authority — `investigator`, `act` and `agenda` are landscape, the same rule as
`Card.isLandscape` — and checked against the old image source it agreed on
7,739 of 7,742. So orientation is decided by type, and the crop is rotated to
match.

**`FaceURL` is not always the front.** For a two-sided card TTS shows the
unrevealed side of a location while ArkhamDB shows the revealed one, and no
field says which is which — the most promising, `locationBack`, gets 311 cards
wrong. `tools/swap_list.json` records the answer for 946 cards, measured once
by comparing the images against `arkhamhorror.app`. It is committed rather than
regenerated, because regenerating it needs the network.

**`UniqueBack` under-reports.** TTS sets it on only some cards that really have
their own back, so a back is also kept when its image merely differs from the
face — guarded by a share count, since 30 generic-back URLs cover 11,909 cards
between them. Measured:

| rule | emitted | missed |
| --- | --- | --- |
| `UniqueBack` only | 4,118 | 182 |
| back ≠ face | 13,455 | 0 (9,813 spurious) |
| `UniqueBack` or (differs and shared ≤ 20) | 4,318 | 26 |

**Art size varies.** `01029` is 423x600, `01001` is 600x423, most are 750x1050.
Never assert an exact size in a test; assert an aspect or a lower bound.

### A reprint borrows the art of the card it reprints

The mod stocks each card once, under its first printing's code. It has no object
for `01501` (Revised Core Roland) or `60108` (a starter deck's Physical
Training), so 52 fronts and 26 backs would be blank beside an identical twin
that has a picture.

`build_assets.py` follows `duplicate_of`/`alternate_of` for the art when a card
has none of its own. It never overrides a card's own picture — verified: all 52
are cases where the mod has no object for that code at all.

The consequence is that **a printing group's art is no longer all distinct.**
All four Roland Banks printings show one portrait; the rows are told apart by
box and number, which is what they are for. 135 groups still have distinct art.

### What the extraction cannot reach

54 cards have no picture at all, and `build_assets.py` names the missing backs
at the end of its run. Of 176 cards that started with no front, 175 were codes
the mod carries no object for — it uses Core Set `01001` for Roland and never
the Revised reprint — and exactly 1 was a crop failure, a truncated cached
sheet. The reprint fallback then recovered 122 of them.

Every one of the 54 has card `text`, and the detail screen shows that instead
via `CardText`. 50 more cards claim a second side whose picture is missing and
draw no flip button.

The complementary case is gone: **no card now flips from a picture to a text
back.** A card the mod misses tends to miss both sides at once, so the text
stands in for the *front* and the flip reaches a real picture — `03076a`
Constance Dumaine is the worked example.

Two hosts do serve the whole gap — `assets.arkhamhorror.app` has all 173 that
TTS lacks, byte-identical to the old source, and `arkhamdb.com/bundles/cards/`
has 106 of them. Neither is used: the app and its pipeline are offline by
design, and a runtime fetch would need a cache, an eviction policy and a
loading state that the `ResizeImage` memory budget rests on not having.

**Markup.** The text these cards fall back to is not a plain string. Across the
202 bodies that render there are six HTML tags (`<b>`, `<i>`, `<hr>`,
`<blockquote>`, `<u>`, `<br>`) and 30 symbol tokens. `CardText.plain` strips the
tags, turns `<hr>` into a blank line, and spells the symbols out as words — the
app has no icon assets to draw them with. An unlisted token is reduced to its
bare name, so a symbol a later box introduces reads as a word rather than as
`[tdc_rune_x]`.

### arkhamdb and the local JSON disagree about the promos

The same card can be a unique printing here and a reprint there. For `98004`:

| | `pack/promo/tdor.json` | arkhamdb API |
| --- | --- | --- |
| illustrator | Brian Valenzuela | Magali Villeneuve |
| flavor | "It **has** worked" | "It **had** worked" |
| `duplicate_of` | absent | `01001` |
| pack | `tdor` | `core`, position 1 |

Because the local record omits `duplicate_of`, `printings` never groups
it with `01001` and it gets its own row — which is the intended behaviour,
every distinct code being its own row. But do not conclude from a differing
illustrator alone that two records are different cards. That conclusion has
already been drawn wrongly once from exactly this field.

### Where the sprite sheets come from

941 sheets, all already cached locally, in two places:

| | Sheets | Wanted images they supply |
| --- | --- | --- |
| `~/Library/Tabletop Simulator/Mods/Images` | 676 | 3,426 |
| the sheet cache | 265 | 4,143 |

The first is what TTS itself downloads when a box is opened in-game, and what
`~/Sync/Python_Scripts/tts_json_backup/tts_json_backup.py` tops up. The second
holds the sheets for boxes never opened — most of the encounter card art.

Both are keyed by TTS's own cache-name scheme: the URL with `/:-_.?=%` stripped.
`sheet_filename` reproduces it, which is why the existing cache can be reused
as-is.

Which boxes to read comes from the SCED `library.json` manifest: the 37 of 191
entries authored by Fantasy Flight Games with type `campaign` or `scenario`.

`DOWNLOAD_SHEETS` is deliberately absent — the extraction is offline. A sheet
that is genuinely missing is reported and its cards fall back to text.

### `extract_card_images.py` was the ancestor, not the build

`~/Sync/Python_Scripts/tts_json_backup/extract_card_images.py` is where this
logic came from. Do not run it against this project: its `APP_SYNC` mode reads
the `arkham-horror` directory for its wanted-file list, its resolution floor and
its identity check — the very tree this pipeline replaced. `tools/extract_tts_images.py`
derives all three locally instead, from the pack files and `type_code`.

## The arkhamdb API

The one thing the app fetches. `GET /api/public/decklist/{id}` returns a
published decklist as JSON, needs no credentials, and sends
`Access-Control-Allow-Origin: *` with `max-age=600`.

Three things about it are easy to get wrong, all verified against the live
service:

| | |
| --- | --- |
| `deck` vs `decklist` | `/api/public/deck/{id}` answers **302 to the login page** for anyone else's deck — it serves the caller's own decks over OAuth2. Only `decklist` is public. The number in a `/deck/view/` URL will not import. |
| A missing id | Answers **200 with an empty body**, not 404. Verified on 52000, 55000 and 99999999. This is the ordinary "no such deck" path. |
| `sideSlots` | `[]` when empty, `{...}` when not — PHP renders an empty associative array as a JSON array. Decoding it as a dictionary outright fails on roughly half the decks on the site. |

`slots` is always an object of code to integer. Every code in every deck
sampled — ids 1 to 63503, spanning 2016 to 2026 — resolves against the bundled
card data, so an unresolvable code is not expected, only guarded against.

The response also carries `xp`, `taboo_id`, `meta` (customisation strings),
`ignoreDeckLimitSlots` and a `previous_deck`/`next_deck` chain. None is used.

## Not used

- `translations/` — 13 languages. The app is English-only.
- `taboos.json` — the tournament ban/tax list.
- Deck validation. `deck_options` and `deck_requirements` describe what a legal
  deck looks like; the app displays decks rather than checking them.
- Card text markup, except on the sides with no picture above. Upstream text
  carries `<b>` tags and `[action]`-style icon tokens; the detail screen is art,
  so only `CardText.plain` deals with them. A general renderer would need icon
  assets this bundle does not carry.
