# Arkham Cards

An offline card reference for Arkham Horror: The Card Game. Browse, search and
filter all 5,928 cards; open one to see its art; read the ten official starter
decks or import your own from arkhamdb.

Flutter, built with Cupertino widgets. iOS, and Android by sideload.

The app shows pictures, not data: the list identifies a card by name, type,
class, box and number, and the detail screen is card art. Everything else is
printed on the card itself. A two-sided card turns over either by a tap on the
art or by the flip button at the right of the navigation bar, and turning over is
the only thing a tap does — a one-sided card does not respond, and shows no flip
button. The exception is 16 cards whose back exists in the data but not as a
picture; they flip to the back's text instead.

Three tabs: Cards, Decks and Settings. The filter is a sheet over the Cards tab,
carrying a live result count. Settings holds one setting, the light/dark/system
theme, and otherwise reports what is bundled.

Search matches the card name only. Traits and card text were once searched too,
which buried the card you were naming under every card that mentions it.

## Decks

The Decks tab lists the **ten Investigator Starter Decks**, derived from the
bundled card data and available offline like everything else. Below them sit
**decks imported from arkhamdb**, by the number in a published decklist's
address — `arkhamdb.com/decklist/view/40838`. An imported deck is saved on the
device and stays readable without a connection; swipe to delete one. This is the
only feature that touches the network.

Only *published decklists* can be imported. A deck under `/deck/view/` is
private to its author and needs an account, so its number will not work.

A deck naming a card this app's data does not carry says so at the bottom rather
than quietly listing fewer cards than it has.

## Building

```sh
/Users/f2pgod/Documents/spyder312/bin/python tools/extract_tts_images.py
/Users/f2pgod/Documents/spyder312/bin/python tools/build_assets.py
flutter run
```

The first script cuts each card out of the Tabletop Simulator sprite sheets it
is stored in. The second reads the card data and those crops and writes
`assets/`: it merges the card data, derives the starter decks, and **transcodes
all 7,617 card images to WebP**, because Flutter's engine cannot decode AVIF and
the one package that can offers no decode-time downsampling — which is what
keeps this app inside its memory budget.

Of the generated assets the two JSON files are committed; `assets/CardImages/`
is 1.19 GB and is not. **A fresh clone therefore has every card and no art, and
the image tests fail until both scripts have been run.**

54 cards have no art at all — the mod carries no object for them — and show
their printed text on the detail screen instead.

## Prebuilt binaries

`.github/workflows/build.yml` builds an APK and an unsigned IPA on a tag or on
demand, and attaches both to the run. Neither is signed for distribution: the
APK carries the debug keys, and the IPA has no signature at all, so **install
it by re-signing with Sideloadly or AltStore**.

CI cannot run the asset pipeline — it reads two upstream checkouts that exist
only on the maintainer's machine — so the transcoded art is published once as
a release asset and downloaded by each run:

```sh
./tools/publish_assets.sh   # 1.21 GB tarball -> the card-images-v2 release
gh workflow run build.yml
gh run download -n arkham-cards-apk
```

`RELEASING.md` has the whole procedure, including what to bump when the art
changes and what the failures mean.

## Where the data comes from

Two upstream sources, neither in this repo and neither version-pinned:

| Source | Provides |
| --- | --- |
| `arkhamdb-json-data` | 5,928 cards in 159 pack files, plus pack, cycle, faction and type names |
| `~/Library/Tabletop Simulator` + the cached SCED boxes | 941 sprite sheets the card art is cut out of |

`tools/extract_tts_images.py` cuts each card out of its sprite sheet.
`tools/build_assets.py` then settles every quirk between the two sources —
reprints filled in from the card they reprint and given its art, the two forms
of card back collapsed into one field, the ten promo printings linked to the
cards they are another edition of, the starter decks derived from `xp` — so no
view has to carry a special case.

**`docs/DATA.md` is the reference for that data.** Most of this project's
complexity lives there, not in the app; if a piece of code looks
over-complicated, the reason is probably on that page.

## Testing

```sh
flutter test    # 120 tests against the real bundled data
flutter analyze
```

Against `assets/` rather than fixtures, because their value is catching a schema
drift upstream that a fixture would hide: 5,928 records each with a row of its
own, 138 variants in 51 groups, all 10 promo printings linked without their own
text being overwritten, 10 starter decks of 33 cards but for the two with extra
signatures, every bundled filename present, every image a real WebP and none of
them a sliver of a card.

## Known gaps

- **54 cards have no bundled art** and show their printed text instead. The
  Tabletop Simulator mod the art comes from carries no object for them.
- **English only.**
- **Android is sideload-only.** 1.19 GB of assets is fine on iOS but exceeds
  Google Play's 1 GB install-time asset-pack limit.

## Layout

```
docs/DATA.md                  the upstream data, in depth
tools/extract_tts_images.py   crop the card art out of TTS sprite sheets
tools/build_assets.py         asset pipeline, run by hand
tools/swap_list.json          which cards TTS stores back-to-front
tools/publish_assets.sh       upload the art to a release, for CI to fetch
lib/models/                   pure Dart, no Flutter imports
  card.dart                   the card record, and the CardValue sentinels
  card_database.dart          loading, indexing, search, printing groups
  card_query.dart             what the user is filtering by
  deck.dart                   a deck: investigator + card codes and quantities
  deck_contents.dart          a deck resolved against the card data, grouped
  deck_store.dart             the starters, the imported decks and their file
  arkhamdb_client.dart        the one network call
lib/views/                    Cupertino, one file per screen
test/                         112 tests, against the real bundled data
.github/workflows/build.yml   APK and unsigned IPA, on a tag or on demand
.github/fetch-images.sh       unpacks the release art onto a runner
RELEASING.md                  how to publish the art and cut a build
```

## For agents and contributors

`AGENTS.md` — commands, conventions, and the traps that have already caused bugs
here. Read before changing anything.
