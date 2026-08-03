import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The appearance preference: the app's one setting.
enum Theme {
  system('System', null),
  light('Light', Brightness.light),
  dark('Dark', Brightness.dark);

  const Theme(this.label, this.brightness);

  final String label;

  /// Null for [Theme.system], which means "do not override the device".
  final Brightness? brightness;

  static const storageKey = 'theme';

  static Theme fromName(String? name) =>
      Theme.values.firstWhere((theme) => theme.name == name,
          orElse: () => Theme.system);
}

/// Holds the theme and writes it back as it changes.
///
/// Owned above the tabs so that the loading spinner and the failure screen
/// honour it too, not just the app proper.
class ThemeController extends ChangeNotifier {
  ThemeController(this._preferences)
    : _theme = Theme.fromName(_preferences?.getString(Theme.storageKey));

  static Future<ThemeController> load() async {
    try {
      return ThemeController(await SharedPreferences.getInstance());
    } catch (_) {
      // An unreadable preference store costs the setting, not the launch.
      return ThemeController(null);
    }
  }

  final SharedPreferences? _preferences;
  Theme _theme;

  Theme get theme => _theme;

  set theme(Theme value) {
    if (value == _theme) return;
    _theme = value;
    _preferences?.setString(Theme.storageKey, value.name);
    notifyListeners();
  }
}
