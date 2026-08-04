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
///
/// The trailing flip button is the same shape of addition: a tap on the art
/// turns the card over too, and neither way is the only one.
/// `test/card_detail_flip_test.dart` pins both.
///
/// Which side is showing is held here rather than down in `_PrintingView`,
/// because the bar's button has to drive it from three levels up. `hasBack`
/// never differs between a card's printings -- checked against all 5,928 -- so
/// the button's presence is decided by the paged card alone and does not depend
/// on which version the page has selected.
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

  /// Whether the card on show is turned over.
  var _showingBack = false;

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
      // Absent on the 3,691 one-sided cards, so the centred title's available
      // width changes as you page and a long name can gain or lose a character.
      // Accepted: a disabled control on 62% of cards is the worse trade.
      trailing: _sequence[_index].hasBack
          ? CupertinoButton(
              // Metrics as the cards list's Filter button, so the bar's
              // toolbar row is the same height here as there.
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              onPressed: () => setState(() => _showingBack = !_showingBack),
              child: const Icon(
                CupertinoIcons.arrow_2_squarepath,
                semanticLabel: 'Turn the card over',
              ),
            )
          : null,
    ),
    child: SafeArea(
      child: PageView.builder(
        controller: _controller,
        // Arriving at a card shows its front. Load-bearing, not tidiness: one
        // flag now serves every page, so without this a swipe off a turned-over
        // card lands on the next card's back.
        onPageChanged: (index) => setState(() {
          _index = index;
          _showingBack = false;
        }),
        // Lazy on purpose: a cleared filter is 5,928 pages, each decoding art
        // at about screen width.
        itemCount: _sequence.length,
        itemBuilder: (context, index) => _CardPage(
          key: ValueKey(_sequence[index].code),
          card: _sequence[index],
          database: widget.database,
          showingBack: _showingBack,
          onShowingBackChanged: (showingBack) =>
              setState(() => _showingBack = showingBack),
        ),
      ),
    ),
  );
}

/// One page: a card's art, with a picker for its other versions.
class _CardPage extends StatefulWidget {
  const _CardPage({
    required this.card,
    required this.database,
    required this.showingBack,
    required this.onShowingBackChanged,
    super.key,
  });

  final model.Card card;
  final CardDatabase database;
  final bool showingBack;
  final ValueChanged<bool> onShowingBackChanged;

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
              child: _PrintingView(
                printing: _selected,
                showingBack: widget.showingBack,
                onFlip: () => widget.onShowingBackChanged(!widget.showingBack),
              ),
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
        // Choosing a version shows its front, not the side the last one
        // happened to be turned to.
        onTap: () {
          setState(() => _selected = printing);
          widget.onShowingBackChanged(false);
        },
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

/// One printing, turned over by a tap on the art or by the bar's flip button.
///
/// Which side is showing belongs to the screen, not here: the bar's button
/// drives the same flag from outside this widget.
class _PrintingView extends StatelessWidget {
  const _PrintingView({
    required this.printing,
    required this.showingBack,
    required this.onFlip,
  });

  /// Roughly screen width. Beyond this only costs memory, and a five-printing
  /// card would decode five of them.
  static const maxPixels = 1200;

  final model.Card printing;
  final bool showingBack;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final filename = showingBack ? printing.backImage : printing.frontImage;
    // A back that exists in the data but not as a picture stands in as text.
    // Only ever the back: a front is a picture or nothing.
    final backText = showingBack && printing.backImage == null
        ? printing.backText
        : null;

    return GestureDetector(
      // A one-sided card ignores taps entirely.
      onTap: printing.hasBack ? onFlip : null,
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
