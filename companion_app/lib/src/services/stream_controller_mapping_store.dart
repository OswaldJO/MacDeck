import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Maps gamepad buttons to keyboard keys for Moonlight streaming.
class StreamControllerBinding {
  const StreamControllerBinding({
    required this.sourceElementId,
    required this.sourceLabel,
    required this.moonlightKeyCode,
    required this.targetLabel,
  });

  final String sourceElementId;
  final String sourceLabel;
  final int moonlightKeyCode;
  final String targetLabel;

  Map<String, dynamic> toJson() => {
        'sourceElementId': sourceElementId,
        'sourceLabel': sourceLabel,
        'moonlightKeyCode': moonlightKeyCode,
        'targetLabel': targetLabel,
      };

  factory StreamControllerBinding.fromJson(Map<String, dynamic> json) {
    return StreamControllerBinding(
      sourceElementId: json['sourceElementId'] as String? ?? '',
      sourceLabel: json['sourceLabel'] as String? ?? '',
      moonlightKeyCode: json['moonlightKeyCode'] as int? ?? 0,
      targetLabel: json['targetLabel'] as String? ?? '',
    );
  }
}

class StreamControllerMappingStore {
  static const _bindingsKey = 'stream.controller.bindings';

  StreamControllerMappingStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<StreamControllerMappingStore> load() async {
    return StreamControllerMappingStore(await SharedPreferences.getInstance());
  }

  List<StreamControllerBinding> get bindings {
    final raw = _prefs.getString(_bindingsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => StreamControllerBinding.fromJson(Map<String, dynamic>.from(entry)))
          .where((binding) => binding.sourceElementId.isNotEmpty && binding.moonlightKeyCode != 0)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveBindings(List<StreamControllerBinding> bindings) async {
    final payload = bindings.map((binding) => binding.toJson()).toList();
    await _prefs.setString(_bindingsKey, jsonEncode(payload));
  }

  String bindingsJson() => jsonEncode(bindings.map((binding) => binding.toJson()).toList());
}
