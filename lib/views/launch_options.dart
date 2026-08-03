/// Which screen to open on, named at launch.
///
/// Driving the app by synthesised taps does not work: the tab bar and list rows
/// are absent from the accessibility tree, and neither AppleScript's clicks nor
/// Quartz events reach it. So a screen that needs screenshotting is named here
/// instead of tapped to.
///
///     flutter run --dart-define=ARKHAM_TAB=decks \
///                 --dart-define=ARKHAM_DECK=starter:mar
abstract final class LaunchOptions {
  /// `cards`, `decks` or `settings`. Anything else opens the cards tab.
  static const tab = String.fromEnvironment('ARKHAM_TAB');

  /// `import` opens the deck import sheet; `filter` opens the filter sheet.
  static const sheet = String.fromEnvironment('ARKHAM_SHEET');

  /// Fills the import sheet in and submits it, fetching for real.
  static const importID = String.fromEnvironment('ARKHAM_IMPORT_ID');

  /// A `Deck.id`, so `starter:mar` or `arkhamdb:40838`.
  static const deck = String.fromEnvironment('ARKHAM_DECK');

  /// A card code, pushing that card's screen over the cards tab.
  static const card = String.fromEnvironment('ARKHAM_CARD');
}
