import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Stable companion device id + friendly name for Mac pairing prompts.
class CompanionDeviceIdentity {
  static const _idKey = 'companion.deviceId';
  static const _nameKey = 'companion.deviceName';

  static Future<String> deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idKey);
    if (id == null || id.isEmpty) {
      final r = Random.secure();
      id = 'companion-${r.nextInt(1 << 32).toRadixString(16)}';
      await prefs.setString(_idKey, id);
    }
    return id;
  }

  static Future<String> deviceName() async {
    final prefs = await SharedPreferences.getInstance();
    var name = prefs.getString(_nameKey);
    if (name == null || name.isEmpty) {
      name = Platform.isIOS ? 'iPhone' : (Platform.isAndroid ? 'Android phone' : 'Companion');
      await prefs.setString(_nameKey, name);
    }
    return name;
  }
}
