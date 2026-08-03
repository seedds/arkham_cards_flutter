import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'bundled_data.dart';

/// The image bundle is the part most likely to break silently: an asset
/// directory that failed to copy, or a filename recorded in cards.json that no
/// longer exists, would show as blank cards rather than as a crash.
void main() {
  test('every referenced image is bundled', () {
    final missing = <String>[];
    for (final card in database.all) {
      for (final filename in [card.frontImage, card.backImage]) {
        if (filename == null) continue;
        if (!File('$imageDirectory/$filename').existsSync()) {
          missing.add(filename);
        }
      }
    }
    expect(missing, isEmpty, reason: 'not in bundle: ${missing.take(5)}');
  });

  test('almost every card has art', () {
    // 27 of 5,928 cards have no bundled art and fall back to a placeholder.
    // Pinned so that a regression in the image pipeline, which would push this
    // number up, fails the build.
    final withoutArt = database.all
        .where((card) => card.frontImage == null && card.backImage == null)
        .toList();
    expect(
      withoutArt.length,
      27,
      reason: 'missing: ${withoutArt.take(5).map((card) => card.code)}',
    );
  });

  test('the bundle holds nothing the cards do not name', () {
    // The asset directory is declared wholesale in pubspec, so an image left
    // behind by an earlier build would be shipped without anything showing it.
    final referenced = {
      for (final card in database.all) ...[
        if (card.frontImage != null) card.frontImage!,
        if (card.backImage != null) card.backImage!,
      ],
    };
    final bundled = Directory(imageDirectory)
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toSet();

    expect(bundled.length, 7742);
    expect(bundled.difference(referenced), isEmpty);
    expect(referenced.difference(bundled), isEmpty);
  });

  test('every image is a WebP', () {
    // Flutter's engine cannot decode the AVIF the Swift bundle held, so an
    // image that slipped through untranscoded would render as nothing at all.
    // Checked by magic number rather than by extension, which is the thing a
    // rename would get wrong.
    final wrong = <String>[];
    for (final file in Directory(imageDirectory).listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.endsWith('.webp')) {
        wrong.add(name);
        continue;
      }
      final header = file.openSync().readSync(12);
      // "RIFF" .... "WEBP"
      final isWebP =
          String.fromCharCodes(header.sublist(0, 4)) == 'RIFF' &&
          String.fromCharCodes(header.sublist(8, 12)) == 'WEBP';
      if (!isWebP) wrong.add(name);
    }
    expect(wrong, isEmpty, reason: 'not WebP: ${wrong.take(5)}');
  });

  test('investigator art is landscape and card art is not', () {
    // Investigator, act and agenda art is stored landscape. A view sizing a
    // landscape picture into a portrait box was one of this project's bugs.
    expect(_dimensions('01001.webp').isLandscape, isTrue, reason: 'Roland');
    expect(_dimensions('01029.webp').isLandscape, isFalse, reason: 'Shotgun');
  });

  test('art is not one uniform size', () {
    // Cards range from 423x600 up to 1050x750, so no view may assume one.
    final shotgun = _dimensions('01029.webp');
    expect(shotgun.height, greaterThan(400));
    expect(shotgun.height, greaterThan(shotgun.width));
  });
}

/// Reads a WebP header far enough to get its dimensions.
///
/// Only the two shapes Pillow writes here: a lossy `VP8 ` frame and the
/// extended `VP8X` form. Enough to check orientation without decoding a
/// gigabyte of art.
({int width, int height, bool isLandscape}) _dimensions(String filename) {
  final bytes = File('$imageDirectory/$filename').readAsBytesSync();
  final format = String.fromCharCodes(bytes.sublist(12, 16));

  late int width;
  late int height;
  switch (format) {
    case 'VP8 ':
      width = (bytes[26] | (bytes[27] << 8)) & 0x3FFF;
      height = (bytes[28] | (bytes[29] << 8)) & 0x3FFF;
    case 'VP8L':
      final bits = bytes[21] | (bytes[22] << 8) | (bytes[23] << 16) |
          (bytes[24] << 24);
      width = (bits & 0x3FFF) + 1;
      height = ((bits >> 14) & 0x3FFF) + 1;
    case 'VP8X':
      width = (bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1;
      height = (bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1;
    default:
      fail('$filename is a $format WebP, which this reader does not know');
  }
  return (width: width, height: height, isLandscape: width > height);
}
