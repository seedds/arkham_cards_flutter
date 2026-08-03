# Working on this project

A Flutter port of an offline iOS card viewer for Arkham Horror: The Card Game.
Read this before changing anything. The Swift original lives at
`~/Documents/arkhamdb`, and its `AGENTS.md` and `docs/DATA.md` remain the
authority on the upstream data — none of that is repeated here.

## Commands

```sh
flutter test                      # 88 tests, ~2s, against the real bundled data
flutter analyze
./tools/crosscheck.sh             # diff the Dart models against the Swift ones

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
| `ARKHAM_SHEET` | `filter` or `import` opens that sheet |
| `ARKHAM_IMPORT_ID` | fills the import sheet in and submits it, fetching for real |
| `ARKHAM_DECK` | pushes one deck — a `Deck.id`, so `starter:mar` |
| `ARKHAM_CARD` | pushes one card by code, so `01001` |

These are compile-time constants, so each needs a rebuild — unlike the Swift
app's environment variables. Driving the app by synthesised taps does not work
any better here than it did there.

## The asset pipeline is not source

`assets/` comes from `tools/build_assets.py`, which reads the Swift project's
`Resources/`. That project's `build_bundle.py` has already settled every data
quirk — reprints filled in, the two forms of card back collapsed, the ten promo
printings linked — so none of it is re-derived here and the two apps cannot
drift on it.

**The one thing this port must do is transcode.** All 7,742 bundled images are
AVIF and Flutter's engine cannot decode AVIF. `flutter_avif` exists but offers
no decode-time downsampling, which is the mechanism the whole memory budget
rests on, so it is not an option. Everything is re-encoded as WebP q80 at native
resolution (1.20 GB) and the two filename fields in `cards.json` are rewritten
to match.

`assets/CardImages/` is gitignored, so **a fresh clone has card data and no art
until the script has been run**, and the image tests fail until then.

## Verify by looking, not just by testing

Every bug found in the Swift project was found in a screenshot. That held here
too: the tests were all green while the rows were 12pt too short, the title was
ungrouped, and the separators ran to the screen edge. Screenshot the screen you
changed, and compare it against the Swift app rather than against your
expectations.

Measure, do not assume. Two things here were wrong on the first attempt and only
a measurement showed it:

- **The back swipe needed no help.** A hand-rolled edge-gesture widget was
  written to stop the pager swallowing it, mirroring what the Swift app had to
  do. A probe showed `CupertinoPageRoute`'s own gesture already wins that
  contest, even mid-pager. The widget was deleted;
  `test/card_detail_gesture_test.dart` pins the behaviour so it is not
  reintroduced.
- **RSS is the wrong memory number.** It read 507 MB and sent me tuning a cache
  that turned out not to matter. `vmmap --summary`'s physical footprint is the
  real figure: 191 MB against the Swift app's 81 MB, both far under the ~345 MB
  the Swift project recorded.

## The cross-check is what proves the port

`flutter test` proves the Dart agrees with assertions someone wrote down. It
cannot prove it agrees with the Swift app being replaced — an ordering rule read
slightly wrong would satisfy both. `tools/crosscheck.sh` builds the Swift models
straight out of the original repo, runs the same dump through each, and diffs
them: card order, every printing group, 18 search queries, every filter count,
and all ten decks. **11,873 lines, byte-identical.** Run it after touching
anything in `lib/models/`.

## Facts that are easy to get wrong

The Swift `AGENTS.md` table of data traps all still applies. These are the ones
specific to the port:

| Claim | Reality |
| --- | --- |
| A missing JSON key and a null one are the same | For `CardValue` they are three states, not two: no key means the field is not printed on this card, `null` means a printed dash, a number means a number. `Card.readValue` tests `containsKey`. Testing `json[k] == null` gives every card without a shroud a printed dash. |
| Dart can fold diacritics | It has no NFD in the core library. `CardDatabase.fold` carries a table of the Latin letters that occur in the 5,928 names. It must match Foundation's folding, which strips a combining mark but leaves `œ` alone — so `Chœur Gothique` is not found by typing "choeur", there or here. |
| A `Set` iterates predictably | It does not, and `DeckContents` sorts slot codes before walking them so `unresolvedCodes` comes out in a fixed order. |
| Sorting by type code is a total order | Every unrecognised type shares one rank, so it needs a tiebreak of its own or section order depends on map iteration. |
| A bare `fontSize` matches SwiftUI | It does not. `.subheadline` and `.caption2` carry line heights; without them the card row stands 12pt shorter than the original. Measured, not guessed. |
| SwiftUI's declared row insets are the whole story | A row also enforces a minimum height. The declared insets are 4pt; the real gap is nearer 9. |
| Flutter's `ImageCache` can be split in two | It cannot. The Swift app kept thumbnails and full-size art apart so opening a card could not evict a screenful of rows; Flutter has one LRU and that guarantee is not expressible. |
| `flutter build ipa --no-codesign` gives an unsigned IPA | There is no such flag on `build ipa`, and its export step needs a signing identity regardless. `--no-codesign` is on `build ios`, and stops at `build/ios/iphoneos/Runner.app`. The workflow zips that into `Payload/` by hand. |
| A CI runner can hold two of these builds | It has 14 GB. A release iOS build leaves two distinct 1.2 GB copies of `Runner.app` — `iphoneos/` and `Release-iphoneos/`, different inodes, not hardlinks — plus dSYMs, and peaks near 8.4 GB. The workflow deletes the intermediates before zipping and prints `df -h`. |

## Conventions

- **Comments explain why, not what.** Most of this project's complexity is
  upstream data quirks and deliberate deviations from the Swift app. Match that.
- **Settle data quirks in the build script, not the app.** Prefer adding to
  `build_bundle.py` in the Swift repo over adding a branch to a widget.
- **Keep the dependency list short.** `path_provider`, `shared_preferences` and
  `flutter_slidable`, and a reason is needed for a fourth. Networking is
  `dart:io`; there is no state-management package.
- **Delete what you orphan.**

## Known deviations from the Swift app

Deliberate, and worth keeping a list of:

- **`uses-material-design: false`.** No Material widget is used, and the icon
  font is dead weight in a bundle already over a gigabyte.
- **The unresolved-cards footer reads "1 card … is"** where the Swift app reads
  "1 card … are". A grammatical bug in the original, fixed rather than ported.
- **`FactionStyle.gradient` is not ported.** No view in the Swift app calls it.
- **Android is sideload-only.** 1.20 GB of assets is fine on iOS (App Store caps
  at 4 GB) but exceeds Google Play's 1 GB install-time asset-pack limit, so a
  Play build would need Play Asset Delivery or a lower-resolution variant.
