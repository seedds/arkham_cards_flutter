# Releasing

How to get an APK and an IPA out of GitHub Actions.

CI cannot build the card art. `tools/build_assets.py` reads two upstream
checkouts that exist only on the maintainer's machine — so the transcoded art
is published once as a release asset, and every CI run downloads it. That is
step 1, and it is only repeated when the art actually changes.

Everything here needs `gh` authenticated against the repo.

## 1. Publish the card art

Only when `assets/CardImages/` has changed — or once, on a repo that has never
had it published.

```sh
/Users/f2pgod/Documents/spyder312/bin/python tools/build_assets.py  # if not already built
./tools/publish_assets.sh
```

The script checks the directory holds exactly 7,742 WebPs, tars them, creates
the `card-images-v1` release and uploads a **1.22 GB** tarball, then deletes the
local copy. Re-running is safe: an existing asset is replaced with `--clobber`.

The tarball is uncompressed on purpose. These are WebP already, and gzip
measured at 1.5% off for minutes of CPU on both ends.

**The upload takes a while and `gh` prints nothing while it runs**, so it will
look like it has hung. To watch from another terminal:

```sh
gh release view card-images-v1
```

Confirm it landed:

```sh
gh release view card-images-v1 --json assets \
  -q '.assets[] | "\(.name)  \(.size) bytes"'
```

Expect `CardImages.tar  1223966720 bytes`. A size well below that means the
upload was cut short — re-run the script.

### When the art changes

Bump the tag in two places together, or CI will keep building the old art:

| | |
| --- | --- |
| `tools/publish_assets.sh` | `TAG` |
| `.github/workflows/build.yml` | `IMAGES_TAG` |

If the image *count* changed, `EXPECTED_IMAGES` also has to move in
`publish_assets.sh`, `build_assets.py`, `build.yml` and
`test/card_images_test.dart`. They are deliberately four separate assertions:
a count that changes in one place only is upstream data drifting unnoticed,
which is the thing they exist to catch.

## 2. Build

```sh
gh workflow run build.yml
gh run watch
```

A tag does the same thing:

```sh
git tag v1.0.0 && git push origin v1.0.0
```

There is no build on ordinary pushes. Each run moves several GB, which is not
worth spending on every commit.

Both jobs fetch the art, count it, then run `flutter analyze` and the 112 tests
before building. `test/card_images_test.dart` checks every filename in
`cards.json` resolves and every file is really a WebP, so it doubles as the
integrity check on the transfer.

Roughly 20-30 minutes, the two jobs in parallel. Free: the repo is public, so
standard runners including macOS are neither metered nor billed.

## 3. Collect the binaries

```sh
gh run download -n arkham-cards-apk
gh run download -n arkham-cards-ipa
```

Or from the run's summary page in a browser.

**Neither is signed for distribution.**

| | |
| --- | --- |
| `app-release.apk` | Signed with the debug keys, per `android/app/build.gradle.kts`. Installs directly by sideload. |
| `Runner.ipa` | No signature at all. **Re-sign with Sideloadly or AltStore** to install on a device. |

## If it fails

**`release not found` in step 2** — step 1 has not finished. The workflow cannot
download a release that does not exist yet.

**`unpacked N images, expected 7742`** — the tarball and `cards.json` have
drifted. Re-run `tools/publish_assets.sh`.

**A disk error, or a job killed mid-build** — the runner has 14 GB and the iOS
build peaks near 8.4 GB of it. A release build leaves two distinct 1.2 GB copies
of `Runner.app` (`iphoneos/` and `Release-iphoneos/` — different inodes, not
hardlinks) plus dSYMs; the workflow already deletes the intermediates before
zipping. Both jobs print `df -h /` after fetching the art and after building,
so the logs show where the headroom went.

**The app builds but shows blank cards** — art that failed to decode. The WebP
assertion in `card_images_test.dart` should have caught it upstream of the
build; check that job's output first.
