# The upstream data

Most of this project's complexity is not in the app — it is in the shape of the
two upstream sources. This document is the reference for that shape. If a piece
of code looks over-complicated, the reason is probably on this page.

Neither source is in this repo, and neither is version-pinned.

| Source | Provides |
| --- | --- |
| `~/Documents/arkhamdb-json-data` | 5,928 cards in 159 pack files, plus pack, cycle, faction, type and encounter-set names |
| `~/Documents/arkham-horror/frontend/public/img/arkham/cards` | 7,947 card images, nearly all `.avif` |

`tools/build_assets.py` reads both and writes `assets/`. The guiding rule:
**settle a data quirk in the build script, so the Dart model does not carry a
special case for it.**

The images are transcoded, not copied: Flutter cannot decode AVIF, so every
one is re-encoded as WebP and each card records the WebP filename. Everything
below describes the source material, which is AVIF.

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

### 2. Front and back are independently optional

`05217` (Nathan Wick) has a back image and **no front image**. A card having
art at all is not implied by it having a back, or the reverse.

- 59 cards have no front art
- 27 cards have no art on either side

Both render `CardPlaceholder`.

### 3. 169 cards were printed more than once

Group sizes: 135 cards have 2 printings, 29 have 3, 3 have 4, and 2 have 5. The
art differs between them, which is the whole reason the detail screen shows a
row per printing.

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

The image directory is keyed by card code with the extension varying:
`01001.avif` for most, `.jpg` for a handful. `build_assets.py` picks one per
code (preferring AVIF) and records the transcoded `.webp` filename on each
card, so the app never guesses an extension or stats the filesystem.

Of the 7,947 source images, 7,742 are referenced by some card and transcoded;
about 205 are orphans — taboo variants (`01033_Mutated15`), per-class Lola
Hayes art (`03006_Guardian`), and near-miss codes.

**Art size varies.** `01029` is 423x600, `01001` is 600x423, others are
750x1050. Never assert an exact size in a test; assert an aspect or a lower
bound. Investigator, act and agenda art is landscape — see `Card.isLandscape`.

### 22 cards want a back the source does not have

`build_assets.py` names them all at the end of its run. They are cards whose
data says two-sided but whose back image is simply not in the dump, so
`back_image` comes out null and the detail screen draws no flip button.

| Group | Count |
| --- | --- |
| Investigators — promos and Starter Decks | 12 |
| The Blob That Ate Everything ELSE! | 7 |
| Story, location, scenario | 3 |

16 of the 22 still carry their back *text*, which is how you can tell this is
a gap in the images rather than a one-sided card. Those 16 flip to that text
via `CardBackText`; the other 6 have neither picture nor text and stay
one-sided. This is the one place the app shows data instead of a picture.

The worked example is `98004` Roland Banks. It is `double_sided`, arkhamdb
serves `98004b.jpg`, and this dump has only `98004.avif` — verified by listing
the source directory, where `01001` has `01001b.avif` and `98004` has no `b`
file under any extension. Nothing was wrong with the app; the picture was
never there. Resist filling these in from the reprint's art — see the trap in
quirk 1.

The boundary is worth stating because it is narrower than it looks: 1,183
cards carry `back_text`, but 1,167 of them also have a back image and keep
showing it. Exactly 16 fall through to text, and no card gains a back it did
not already claim.

**Markup.** These backs are not plain strings. Across the 16 there are seven
HTML tags (`<b>`, `<i>`, `<hr>`, `<blockquote>` and closers) and nine symbol
tokens (`[guardian]`, `[skull]`, `[elder_thing]`…). `CardBackText.plain`
strips the tags, turns `<hr>` into a blank line, and spells the symbols out as
words — the app has no icon assets to draw them with.

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

### The near-miss filenames

34 of the 58 cards with no front art have an image in the source directory
under an almost-matching name: `04117a` needs `04117.avif`, `03325` needs
`03325a.avif`. A suffix-matching rule in `build_assets.py` would cut the gap
from 58 to about 24. Not implemented — it is a guess about upstream naming, and
guessing wrong means showing the wrong card's art, which is worse than showing
a placeholder.

### `extract_card_images.py` is upstream, not part of the build

`~/Sync/Python_Scripts/tts_json_backup/extract_card_images.py` crops card art
out of Tabletop Simulator sprite sheets. Its `APP_SYNC` mode writes *into* the
`arkham-horror` directory this project reads, so it sits upstream of
`build_assets.py`, not inside it.

Do not wire it into this build. It needs network access, a Tabletop Simulator
save file, and hours of runtime. Its own standalone output covers only 5,437
card codes against the 5,869 the `arkham-horror` directory already has.

To improve the art: run that script in its own directory, then re-run
`tools/build_assets.py` here.

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
- Card text markup, except on the 16 backs above. Upstream text carries `<b>`
  tags and `[action]`-style icon tokens; the detail screen is art, so only
  `CardBackText.plain` deals with them. A general renderer would need icon
  assets this bundle does not carry.
