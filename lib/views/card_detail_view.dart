import 'package:flutter/cupertino.dart';

import '../models/card.dart' as model;
import '../models/card_database.dart';
import 'card_back_text.dart';
import 'card_image_view.dart';
import 'card_row.dart';

/// One card's art, and its other versions underneath.
///
/// Pages sideways through the list it was opened from, so a swipe moves to the
/// next card in the order just read. The bar's title follows the pager, which is
/// the one thing on this screen that names the 27 cards holding no art.
///
/// The bar costs 44pt of the art. On a 6.3-inch screen a portrait card still
/// gets the 505pt it wants; on a 4.7-inch one the height clamp in `_CardPage`
/// starts biting and it gets 449 of the 480 it asks for. Measured, and accepted:
/// a screen with no visible way off it is worse than a card 31pt shorter.
///
/// The edge swipe still works and is still worth pinning. The bar's button is an
/// addition, not a replacement: `CupertinoPageRoute`'s own back gesture beats a
/// full-width `PageView` in the arena, including mid-pager where the drag is
/// ambiguous, and a hand-rolled edge recogniser written for this was measured to
/// be unnecessary. `test/card_detail_gesture_test.dart` pins both ways back,
/// because an added edge widget could quietly take the swipe away again.
class CardDetailView extends StatefulWidget {
  const CardDetailView({
    required this.card,
    required this.cards,
    required this.database,
    super.key,
  });

  final model.Card card;
  final List<model.Card> cards;
  final CardDatabase database;

  @override
  State<CardDetailView> createState() => _CardDetailViewState();
}

class _CardDetailViewState extends State<CardDetailView> {
  late final List<model.Card> _sequence;
  late final PageController _controller;

  /// Which card the bar is naming. Held here rather than read from the
  /// controller because `page` is a double mid-drag and null before first
  /// layout, and the title should change once, on arrival.
  late int _index;

  @override
  void initState() {
    super.initState();
    // Never empty, and never opens on a card the caller did not ask for.
    _sequence = widget.cards.contains(widget.card)
        ? widget.cards
        : [widget.card];
    _index = _sequence.indexOf(widget.card).clamp(0, _sequence.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
    // The leading chevron is implied, and comes out bare: neither route that
    // pushes this screen sets a `title`, so Flutter has no previous page to
    // name and draws the chevron alone.
    navigationBar: CupertinoNavigationBar(
      // Ellipsised because the toolbar will not shrink it and the longest name
      // runs to 46 characters ("Return to Disappearance at the Twilight
      // Estate").
      middle: Text(
        _sequence[_index].name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    child: SafeArea(
      child: PageView.builder(
        controller: _controller,
        onPageChanged: (index) => setState(() => _index = index),
        // Lazy on purpose: a cleared filter is 5,928 pages, each decoding art
        // at about screen width.
        itemCount: _sequence.length,
        itemBuilder: (context, index) => _CardPage(
          key: ValueKey(_sequence[index].code),
          card: _sequence[index],
          database: widget.database,
        ),
      ),
    ),
  );
}

/// One page: a card's art, with a picker for its other versions.
class _CardPage extends StatefulWidget {
  const _CardPage({required this.card, required this.database, super.key});

  final model.Card card;
  final CardDatabase database;

  @override
  State<_CardPage> createState() => _CardPageState();
}

class _CardPageState extends State<_CardPage> {
  /// Enough for about two rows.
  static const _minimumPickerHeight = 96.0;

  late model.Card _selected = widget.card;
  late final List<model.Card> _printings = widget.database.printings(
    widget.card,
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final hasVersions = _printings.length > 1;
      final width = constraints.maxWidth - 32;
      // Both figures are inside the padding below, so each is the constraint
      // less that padding's insets on its axis: 16+16 across, 8+0 down. The
      // clamp measures the art against `available`, so overstating it here
      // would make the clamp bite early on a small screen.
      final available = constraints.maxHeight - 8;
      final reserved = hasVersions ? _minimumPickerHeight : 0.0;
      // A height multiplier, not the width-over-height ratio: portrait art is
      // 1.4 times as tall as it is wide.
      final aspect = _selected.isLandscape ? 1 / 1.4 : 1.4;

      return Padding(
        // No bottom inset: it sat outside the picker's ListView, so its 16pt
        // was neither usable height nor scrollable slack -- a dead strip above
        // the tab bar hairline. The SafeArea above already ends the content
        // region on that hairline, so the last row clears the bar without it.
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            SizedBox(
              width: width,
              // The clamp only bites in landscape, where an unclamped portrait
              // card would want more than the whole screen and leave the rows
              // nothing.
              height: (width * aspect).clamp(0.0, available - reserved),
              child: _PrintingView(printing: _selected),
            ),
            if (hasVersions) ...[
              const SizedBox(height: 8),
              Container(
                height: 1 / MediaQuery.devicePixelRatioOf(context),
                color: CupertinoColors.separator.resolveFrom(context),
              ),
              const SizedBox(height: 8),
              Expanded(child: _versionPicker(context)),
            ] else
              const Spacer(),
          ],
        ),
      );
    },
  );

  /// Every version, including the one on show, so the list does not reshuffle
  /// under the finger that just tapped.
  Widget _versionPicker(BuildContext context) => ListView.separated(
    itemCount: _printings.length,
    separatorBuilder: (context, index) => Container(
      height: 1 / MediaQuery.devicePixelRatioOf(context),
      color: CupertinoColors.separator.resolveFrom(context),
    ),
    itemBuilder: (context, index) {
      final printing = _printings[index];
      final isSelected = printing == _selected;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = printing),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: CardRow(card: printing)),
              if (isSelected)
                Icon(
                  CupertinoIcons.check_mark,
                  size: 16,
                  color: CupertinoTheme.of(context).primaryColor,
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// One printing, turned over by a tap.
class _PrintingView extends StatefulWidget {
  const _PrintingView({required this.printing});

  /// Roughly screen width. Beyond this only costs memory, and a five-printing
  /// card would decode five of them.
  static const maxPixels = 1200;

  final model.Card printing;

  @override
  State<_PrintingView> createState() => _PrintingViewState();
}

class _PrintingViewState extends State<_PrintingView> {
  var _showingBack = false;

  @override
  void didUpdateWidget(_PrintingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Choosing another version shows its front, not the side the last one
    // happened to be turned to.
    if (oldWidget.printing != widget.printing) _showingBack = false;
  }

  @override
  Widget build(BuildContext context) {
    final printing = widget.printing;
    final filename = _showingBack ? printing.backImage : printing.frontImage;
    // A back that exists in the data but not as a picture stands in as text.
    // Only ever the back: a front is a picture or nothing.
    final backText = _showingBack && printing.backImage == null
        ? printing.backText
        : null;

    return GestureDetector(
      // A one-sided card ignores taps entirely.
      onTap: printing.hasBack
          ? () => setState(() => _showingBack = !_showingBack)
          : null,
      child: Semantics(
        button: printing.hasBack,
        hint: printing.hasBack ? 'Tap to turn the card over' : null,
        child: backText != null
            // Its own scroll view: the screen no longer provides one and the
            // longest back runs to 935 characters.
            ? SingleChildScrollView(
                child: CardBackText(card: printing, text: backText),
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x54000000),
                      blurRadius: 12,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: CardImageView(
                  card: printing,
                  filename: filename,
                  maxPixels: _PrintingView.maxPixels,
                  cornerRadius: 12,
                ),
              ),
      ),
    );
  }
}
