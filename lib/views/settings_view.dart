import 'package:flutter/cupertino.dart';

import '../models/card_database.dart';
import 'number_format.dart';
import 'theme.dart';

/// Appearance, plus what the app is and what is in it.
///
/// Appearance is the only thing to configure: the app has no account and syncs
/// nothing. The card data carries no version of its own either -- `cards.json`
/// is a bare array and neither upstream source is version-pinned -- so the rest
/// reports what can actually be counted.
class SettingsView extends StatelessWidget {
  const SettingsView({
    required this.database,
    required this.themeController,
    super.key,
  });

  static const appVersion = '1.0 (1)';

  final CardDatabase database;
  final ThemeController themeController;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    ),
    child: CustomScrollView(
      slivers: [
        const CupertinoSliverNavigationBar(largeTitle: Text('Settings')),
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('Appearance'),
            children: [
              CupertinoListTile.notched(
                title: const Text('Theme'),
                additionalInfo: Text(themeController.theme.label),
                trailing: const CupertinoListTileChevron(),
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (context) =>
                        _ThemePicker(controller: themeController),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('Cards'),
            children: [
              CupertinoListTile.notched(
                title: const Text('Cards'),
                additionalInfo: Text(grouped(database.all.length)),
              ),
              CupertinoListTile.notched(
                title: const Text('Cycles'),
                additionalInfo: Text('${database.cycles.length}'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('About'),
            footer: const Text(
              'Every card, image and starter deck is bundled with the app and '
              'works offline. Importing a deck is the one thing that reaches '
              'the network: it fetches a published decklist from arkhamdb and '
              'saves it on this device.',
            ),
            children: const [
              CupertinoListTile.notched(
                title: Text('Version'),
                additionalInfo: Text(appVersion),
              ),
            ],
          ),
        ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    ),
  );
}

class _ThemePicker extends StatefulWidget {
  const _ThemePicker({required this.controller});

  final ThemeController controller;

  @override
  State<_ThemePicker> createState() => _ThemePickerState();
}

class _ThemePickerState extends State<_ThemePicker> {
  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    backgroundColor: CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    ),
    navigationBar: const CupertinoNavigationBar(middle: Text('Theme')),
    child: SafeArea(
      child: ListView(
        children: [
          CupertinoListSection.insetGrouped(
            children: [
              for (final theme in Theme.values)
                CupertinoListTile.notched(
                  title: Text(theme.label),
                  onTap: () {
                    widget.controller.theme = theme;
                    setState(() {});
                  },
                  trailing: widget.controller.theme == theme
                      ? Icon(
                          CupertinoIcons.check_mark,
                          size: 20,
                          color: CupertinoTheme.of(context).primaryColor,
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
