# Working on this project

An offline card viewer for Arkham Horror: The Card Game, in Flutter. Read this
before changing anything. `docs/DATA.md` is the authority on the upstream data
and is not repeated here — most of this project's complexity is described there
rather than in the code.

## Commands

```sh
flutter test                      # 112 tests, ~2s, against the real bundled data
flutter analyze

/Users/f2pgod/Documents/spyder312/bin/python tools/build_assets.py
./tools/publish_assets.sh         # push that art to the release CI builds from
gh workflow run build.yml         # APK and unsigned IPA -- see RELEASING.md
```

Use that Python for the asset script: it has Pillow, which the system one does
not.

To see a screen without tapping through the simulator, name it at build time:

```sh
flutter build ios --simulator --debug --dart-define=ARKHAM_TAB=decks
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted com.f2pgod.arkhamCards
xcrun simctl io booted screenshot /tmp/shot.png
```

| Define | Effect |
| --- | --- |
| `ARKHAM_TAB` | `cards`, `decks` or `settings` |
| `ARKHAM_SHEET` | `filter`, `import` or `sort` opens that sheet |
| `ARKHAM_SORT` | a `CardSort` name, so `name` |
| `ARKHAM_IMPORT_ID` | fills the import sheet in and submits it, fetching for real |
| `ARKHAM_DECK` | pushes one deck — a `Deck.id`, so `starter:mar` |
| `ARKHAM_CARD` | pushes one card by code, so `01001` |

These are compile-time constants, so each needs a rebuild. **Driving the app by
synthesised taps does not work** — the tab bar and list rows are not reachable
that way. Add a define for the screen you need instead.

## The asset pipeline is not source

`assets/` comes from `tools/build_assets.py`, which reads two upstream
checkouts that are not in this repo and are not version-pinned:

| Source | Provides |
| --- | --- |
| `~/Documents/arkhamdb-json-data` | 5,928 cards in 159 pack files, plus pack, cycle, faction and type names |
| `~/Documents/arkham-horror/frontend/public/img/arkham/cards` | 7,947 card images, nearly all AVIF |

The script settles every data quirk — reprints filled in, the two forms of card
back collapsed to one field, the ten promo printings linked, the starter decks
derived from `xp` — so no widget carries a special case for any of it.
`docs/DATA.md` explains each one.

**It also transcodes.** Flutter's engine cannot decode AVIF. `flutter_avif`
exists but offers no decode-time downsampling, which is the mechanism the whole
memory budget rests on, so it is not an option. Every referenced image is
re-encoded as WebP q80 at native resolution (1.20 GB) and each card records the
`.webp` filename.

`assets/CardImages/` is gitignored, so **a fresh clone has card data and no art
until the script has been run**, and the image tests fail until then. The two
JSON files are committed.

Re-running is cheap: an image whose source has not changed is skipped, so only
what actually moved is transcoded.

## Verify by looking, not just by testing

Tests pin data invariants well and say nothing about whether the screen is
right. The tests were all green while the rows were 12pt too short, the title
was ungrouped, and the separators ran to the screen edge. Screenshot the screen
you changed.

Measure, do not assume. Two things here were wrong on the first attempt and only
a measurement showed it:

- **The back swipe needed no help.** A hand-rolled edge-gesture widget was
  written to stop the pager swallowing it. A probe showed
  `CupertinoPageRoute`'s own gesture already wins that contest, even mid-pager.
  The widget was deleted; `test/card_detail_gesture_test.dart` pins the
  behaviour so it is not reintroduced.
- **RSS is the wrong memory number.** It read 507 MB and sent me tuning a cache
  that turned out not to matter. `vmmap --summary`'s physical footprint is the
  real figure: 191 MB.

## Facts that are easy to get wrong

`docs/DATA.md` carries the upstream data traps. These are the ones about this
codebase:

| Claim | Reality |
| --- | --- |
| A missing JSON key and a null one are the same | For `CardValue` they are three states, not two: no key means the field is not printed on this card, `null` means a printed dash, a number means a number. `Card.readValue` tests `containsKey`. Testing `json[k] == null` gives every card without a shroud a printed dash. |
| Dart can fold diacritics | It has no NFD in the core library. `CardDatabase.fold` carries a table of the Latin letters that occur in the 5,928 names. It strips a combining mark but leaves `œ` alone — so `Chœur Gothique` is not found by typing "choeur". |
| A `Set` iterates predictably | It does not, and `DeckContents` sorts slot codes before walking them so `unresolvedCodes` comes out in a fixed order. |
| Sorting by type code is a total order | Every unrecognised type shares one rank, so it needs a tiebreak of its own or section order depends on map iteration. |
| `List.sort` is stable | It is not, and hundreds of cards share a name. `CardSort.name` breaks ties on release order then code, or a card's versions scatter. |
| A bare `fontSize` gives the right row height | It does not: the system line height for a size is not implied by the size. Without it the card row stands 12pt shorter. Measured, not guessed. |
| A list row's declared insets are the whole story | A row also enforces a minimum height. The declared insets are 4pt; the real gap is nearer 9. |
| A tab is inset above the tab bar | Only if it scrolls with a `BoxScrollView`. The tab bar is translucent, so `CupertinoTabScaffold` reports its 60pt as a `MediaQuery` padding *hint* and lets content draw behind it. `ListView` consumes that hint; `CustomScrollView` is not a `BoxScrollView` and consumes nothing, so the decks and settings tabs each need `MediaQuery.paddingOf(context).bottom` on their trailing sliver or the last row sits under the bar. |
| Flutter's `ImageCache` can be split in two | It cannot — one LRU, so there is no way to stop an opened card evicting a screenful of rows. A budget well above the row working set stands in for that. |
| Sorting the browse list can reorder `all` | It cannot. The cycle list is derived by walking `all` in bundled order, so a sort applies to the result and never to the field. |
| `flutter build ipa --no-codesign` gives an unsigned IPA | There is no such flag on `build ipa`, and its export step needs a signing identity regardless. `--no-codesign` is on `build ios`, and stops at `build/ios/iphoneos/Runner.app`. The workflow zips that into `Payload/` by hand. |
| A CI runner can hold two of these builds | It has 14 GB. A release iOS build leaves two distinct 1.2 GB copies of `Runner.app` — `iphoneos/` and `Release-iphoneos/`, different inodes, not hardlinks — plus dSYMs, and peaks near 8.4 GB. The workflow deletes the intermediates before zipping and prints `df -h`. |

## Conventions

- **Comments explain why, not what.** Most of this project's complexity is
  upstream data quirks and measured deviations from what looks obvious. Match
  that.
- **Settle data quirks in the build script, not the app.** Prefer adding to
  `tools/build_assets.py` over adding a branch to a widget, and record the
  reasoning in `docs/DATA.md`.
- **Keep the dependency list short.** `path_provider`, `shared_preferences` and
  `flutter_slidable`, and a reason is needed for a fourth. Networking is
  `dart:io`; there is no state-management package.
- **Delete what you orphan.**

## Decisions worth not relitigating

- **`uses-material-design: false`.** No Material widget is used, and the icon
  font is dead weight in a bundle already over a gigabyte.
- **The detail screen is art, not data.** Everything but name, type, class, box
  and number is printed on the card itself. The one exception is the 16 cards
  whose back exists as text but not as a picture.
- **Search matches the card name only.** Traits and card text were once
  searched too, which buried the card you were naming under every card that
  mentions it.
- **Android is sideload-only.** 1.20 GB of assets is fine on iOS (App Store caps
  at 4 GB) but exceeds Google Play's 1 GB install-time asset-pack limit, so a
  Play build would need Play Asset Delivery or a lower-resolution variant.
