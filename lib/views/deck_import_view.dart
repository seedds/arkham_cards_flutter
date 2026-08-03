import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../models/arkhamdb_client.dart';
import '../models/deck_store.dart';
import 'launch_options.dart';

/// Import a published decklist by its arkhamdb number.
///
/// The number is the awkward part of this screen, so it is what the text
/// explains: arkhamdb has two kinds of deck page and only the published one can
/// be fetched without an account. Someone pasting the number from a
/// `/deck/view/` URL gets "no published decklist has that number", which is true
/// but tells them nothing, so the form says which URL to read it from first.
class DeckImportView extends StatefulWidget {
  const DeckImportView({
    required this.store,
    this.scrollController,
    super.key,
  });

  final DeckStore store;

  /// The sheet's own controller, so dragging this form down dismisses it.
  final ScrollController? scrollController;

  @override
  State<DeckImportView> createState() => _DeckImportViewState();
}

class _DeckImportViewState extends State<DeckImportView> {
  // Filled and submitted on appearance by --dart-define=ARKHAM_IMPORT_ID, so a
  // real import can be screenshotted without typing into the simulator.
  late final _controller = TextEditingController(text: LaunchOptions.importID);
  String? _error;
  var _isImporting = false;

  @override
  void initState() {
    super.initState();
    if (LaunchOptions.importID.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _deckID {
    final id = int.tryParse(_controller.text.trim());
    return id != null && id > 0 ? id : null;
  }

  Future<void> _load() async {
    final id = _deckID;
    if (id == null) return;
    setState(() {
      _isImporting = true;
      _error = null;
    });
    try {
      await widget.store.importDecklist(id);
      if (mounted) Navigator.of(context).pop();
      return;
    } on ArkhamDBError catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not import that deck.');
    }
    if (mounted) setState(() => _isImporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final canImport = _deckID != null && !_isImporting;

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
        context,
      ),
      navigationBar: CupertinoNavigationBar(
        automaticallyImplyLeading: false,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        middle: const Text('Import Deck'),
      ),
      child: SafeArea(
        child: ListView(
          controller: widget.scrollController,
          children: [
            CupertinoListSection.insetGrouped(
              footer: const Text(
                "The number in a published decklist's address: "
                'arkhamdb.com/decklist/view/40838. A deck under /deck/view/ '
                'is private to its author and cannot be imported.',
              ),
              children: [
                CupertinoTextFormFieldRow(
                  controller: _controller,
                  placeholder: 'Decklist number',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() => _error = null),
                  onFieldSubmitted: (_) => canImport ? _load() : null,
                ),
              ],
            ),
            if (_error case final String error)
              CupertinoListSection.insetGrouped(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          size: 15,
                          color: CupertinoColors.systemRed,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            error,
                            style: const TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.systemRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            CupertinoListSection.insetGrouped(
              footer: const Text(
                'The deck is saved on this device and stays readable without '
                'a connection.',
              ),
              children: [
                CupertinoListTile.notched(
                  onTap: canImport ? _load : null,
                  title: Text(
                    'Import',
                    style: TextStyle(
                      color: canImport
                          ? CupertinoTheme.of(context).primaryColor
                          : CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ),
                  trailing: _isImporting
                      ? const CupertinoActivityIndicator()
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
