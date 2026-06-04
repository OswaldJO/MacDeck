import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Primary text color for the companion app UI (Settings → Appearance).
class CompanionAppearanceSettings {
  static const _primaryTextColorKey = 'companion.appearance.primaryTextColor';

  /// Increment to rebuild [MaterialApp] theme after a color change.
  static final ValueNotifier<int> themeRevision = ValueNotifier<int>(0);

  /// Default near-white body text on dark backgrounds.
  static const Color defaultPrimaryText = Color(0xFFE8EAED);

  static const List<({String label, Color color})> presetTextColors = [
    (label: 'White', color: Color(0xFFE8EAED)),
    (label: 'Purple', color: Color(0xFFBB86FC)),
    (label: 'Lavender', color: Color(0xFFD0BCFF)),
    (label: 'Blue', color: Color(0xFF6EB5FF)),
    (label: 'Mint', color: Color(0xFF80CBC4)),
    (label: 'Peach', color: Color(0xFFFFB4A2)),
  ];

  CompanionAppearanceSettings(this._prefs);

  final SharedPreferences _prefs;

  static Future<CompanionAppearanceSettings> load() async {
    return CompanionAppearanceSettings(await SharedPreferences.getInstance());
  }

  Color get primaryTextColor {
    final stored = _prefs.getInt(_primaryTextColorKey);
    if (stored == null) return defaultPrimaryText;
    return Color(stored);
  }

  Future<void> setPrimaryTextColor(Color color) async {
    await _prefs.setInt(_primaryTextColorKey, color.toARGB32());
    themeRevision.value++;
  }
}
