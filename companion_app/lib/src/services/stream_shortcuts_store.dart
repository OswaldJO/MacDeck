import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import '../models/stream_shortcut.dart';

class StreamShortcutsStore {
  static const _shortcutsKey = 'stream.shortcuts';

  StreamShortcutsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<StreamShortcutsStore> load() async {
    return StreamShortcutsStore(await SharedPreferences.getInstance());
  }

  List<StreamShortcut> get shortcuts {
    final raw = _prefs.getString(_shortcutsKey);
    if (raw == null || raw.isEmpty) {
      return [StreamShortcut.defaultCloseApp()];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [StreamShortcut.defaultCloseApp()];
      final list = decoded
          .whereType<Map>()
          .map((e) => StreamShortcut.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.id.isNotEmpty && s.moonlightKeyCodes.isNotEmpty)
          .toList();
      return _migrateCloseApp(list.isEmpty ? [StreamShortcut.defaultCloseApp()] : list);
    } catch (_) {
      return [StreamShortcut.defaultCloseApp()];
    }
  }

  /// One-time update when default Close app was still ⌘⌥Esc.
  static List<StreamShortcut> _migrateCloseApp(List<StreamShortcut> list) {
    return list.map((shortcut) {
      if (shortcut.id != 'close_app') return shortcut;
      if (!_codesEqual(shortcut.moonlightKeyCodes, StreamShortcut.legacyCloseAppKeyCodes)) {
        return shortcut;
      }
      return StreamShortcut.defaultCloseApp();
    }).toList();
  }

  static bool _codesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Persists migrated Close app default if the stored chord was still ⌘⌥Esc.
  static Future<void> migrateCloseAppDefaultIfNeeded() async {
    final store = await load();
    final current = store.shortcuts;
    final migrated = _migrateCloseApp(current);
    if (!_listEqualsShortcuts(current, migrated)) {
      await store.saveAll(migrated);
    }
  }

  static bool _listEqualsShortcuts(List<StreamShortcut> a, List<StreamShortcut> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].keyLabel != b[i].keyLabel) return false;
      if (!_codesEqual(a[i].moonlightKeyCodes, b[i].moonlightKeyCodes)) return false;
    }
    return true;
  }

  Future<void> saveAll(List<StreamShortcut> items) async {
    final payload = items.map((s) => s.toJson()).toList();
    await _prefs.setString(_shortcutsKey, jsonEncode(payload));
  }

  Future<StreamShortcut> addNew({
    required String name,
    required List<int> moonlightKeyCodes,
    required String keyLabel,
  }) async {
    final shortcut = StreamShortcut(
      id: 'shortcut_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      moonlightKeyCodes: moonlightKeyCodes,
      keyLabel: keyLabel,
    );
    final updated = [...shortcuts, shortcut];
    await saveAll(updated);
    return shortcut;
  }

  Future<void> upsert(StreamShortcut shortcut) async {
    final updated = [
      ...shortcuts.where((s) => s.id != shortcut.id),
      shortcut,
    ];
    await saveAll(updated);
  }

  Future<void> remove(String id) async {
    var updated = shortcuts.where((s) => s.id != id).toList();
    if (updated.isEmpty) {
      updated = [StreamShortcut.defaultCloseApp()];
    }
    await saveAll(updated);
  }

  String shortcutsJson() => jsonEncode(shortcuts.map((s) => s.toJson()).toList());
}
