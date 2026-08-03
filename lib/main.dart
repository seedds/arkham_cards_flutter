import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'models/card_database.dart';
import 'models/deck_store.dart';
import 'views/main_tab_view.dart';
import 'views/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The cards are decoded once at launch and held for the life of the process,
  // so nothing after this reads from disk. Card art is the exception, and is
  // decoded to the size being drawn -- see CardImageView.
  //
  // Sized to the working set rather than to a round number. A 168pt row
  // thumbnail costs at most 0.11 MB decoded and a 1200px detail image 5.8 MB,
  // so 420 rows and a handful of open cards need about 100 MB between them.
  //
  // Thumbnails and full-size art cannot be kept apart: Flutter's cache is a
  // single LRU, so there is no way to stop one opened card evicting a
  // screenful of rows. A budget this far above the row working set is what
  // stands in for that guarantee. Raising it to 288 MB
  // was measured to make no difference to the footprint at rest, so the
  // smaller number is the honest one.
  PaintingBinding.instance.imageCache
    ..maximumSize = 500
    ..maximumSizeBytes = 100 * 1024 * 1024;

  runApp(const ArkhamCardsApp());
}

class ArkhamCardsApp extends StatefulWidget {
  const ArkhamCardsApp({super.key});

  @override
  State<ArkhamCardsApp> createState() => _ArkhamCardsAppState();
}

class _ArkhamCardsAppState extends State<ArkhamCardsApp> {
  late final Future<_Loaded> _loading = _load();

  Future<_Loaded> _load() async {
    final themeController = await ThemeController.load();
    final cardsJson = await rootBundle.loadString('assets/cards.json');
    final decksJson = await rootBundle.loadString('assets/decks.json');
    return _Loaded(
      database: CardDatabase.fromJson(cardsJson),
      deckStore: await DeckStore.load(decksJson: decksJson),
      themeController: themeController,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_Loaded>(
    future: _loading,
    builder: (context, snapshot) {
      final loaded = snapshot.data;
      // The theme wraps the spinner and the failure screen too, not just the
      // app proper, so a dark-mode launch does not flash white.
      return ListenableBuilder(
        listenable: loaded?.themeController ?? _neverChanges,
        builder: (context, _) => CupertinoApp(
          title: 'Arkham Cards',
          debugShowCheckedModeBanner: false,
          theme: CupertinoThemeData(
            brightness: loaded?.themeController.theme.brightness,
          ),
          home: switch ((loaded, snapshot.error)) {
            (final _Loaded loaded, _) => MainTabView(
              database: loaded.database,
              deckStore: loaded.deckStore,
              themeController: loaded.themeController,
            ),
            (_, final Object error) => _FailedView(message: '$error'),
            _ => const _LoadingView(),
          },
        ),
      );
    },
  );
}

final _neverChanges = ValueNotifier<void>(null);

class _Loaded {
  const _Loaded({
    required this.database,
    required this.deckStore,
    required this.themeController,
  });

  final CardDatabase database;
  final DeckStore deckStore;
  final ThemeController themeController;
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) => const CupertinoPageScaffold(
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CupertinoActivityIndicator(),
          SizedBox(height: 12),
          Text('Loading cards\u2026'),
        ],
      ),
    ),
  );
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 52,
              color: CupertinoColors.tertiaryLabel.resolveFrom(context),
            ),
            const SizedBox(height: 12),
            const Text(
              'Could not load cards',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
