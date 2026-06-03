import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/gamepad_elements.dart';
import '../data/moonlight_key_codes.dart';

/// Keyboard chord assigned to a logical gamepad element (native + Moonlight paths).
class StreamControllerElementMapping {
  const StreamControllerElementMapping({
    required this.sourceElementId,
    required this.sourceLabel,
    required this.moonlightKeyCodes,
    required this.targetLabel,
    this.physicalKeyCode,
    this.manualPhysicalLink = false,
  });

  final String sourceElementId;
  final String sourceLabel;
  final List<int> moonlightKeyCodes;
  final String targetLabel;
  final int? physicalKeyCode;
  final bool manualPhysicalLink;

  bool get hasKeyboardMapping => moonlightKeyCodes.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'sourceElementId': sourceElementId,
        'sourceLabel': sourceLabel,
        'moonlightKeyCodes': moonlightKeyCodes,
        'targetLabel': targetLabel,
        if (physicalKeyCode != null) 'physicalKeyCode': physicalKeyCode,
        'manualPhysicalLink': manualPhysicalLink,
      };

  factory StreamControllerElementMapping.fromJson(Map<String, dynamic> json) {
    final elementId = json['sourceElementId'] as String? ?? '';
    final element = gamepadElementById(elementId);
    final codes = _parseKeyCodes(json);
    final label = json['targetLabel'] as String? ?? _labelForCodes(codes);
    return StreamControllerElementMapping(
      sourceElementId: elementId,
      sourceLabel: json['sourceLabel'] as String? ?? element?.label ?? elementId,
      moonlightKeyCodes: codes,
      targetLabel: label,
      physicalKeyCode: json['physicalKeyCode'] as int?,
      manualPhysicalLink: json['manualPhysicalLink'] as bool? ?? false,
    );
  }

  static List<int> _parseKeyCodes(Map<String, dynamic> json) {
    final multi = json['moonlightKeyCodes'];
    if (multi is List) {
      return multi.map((e) => (e as num).toInt()).where((c) => c != 0).toList();
    }
    final single = json['moonlightKeyCode'] as int? ?? 0;
    return single != 0 ? [single] : [];
  }

  static String _labelForCodes(List<int> codes) {
    if (codes.isEmpty) return 'Unmapped';
    final parts = codes
        .map((c) => moonlightKeyByCode(c)?.label ?? 'Key')
        .toList();
    return parts.join(' + ');
  }

  StreamControllerElementMapping copyWith({
    List<int>? moonlightKeyCodes,
    String? targetLabel,
    int? physicalKeyCode,
    bool? manualPhysicalLink,
    bool clearPhysicalKeyCode = false,
  }) {
    return StreamControllerElementMapping(
      sourceElementId: sourceElementId,
      sourceLabel: sourceLabel,
      moonlightKeyCodes: moonlightKeyCodes ?? this.moonlightKeyCodes,
      targetLabel: targetLabel ?? this.targetLabel,
      physicalKeyCode: clearPhysicalKeyCode ? null : (physicalKeyCode ?? this.physicalKeyCode),
      manualPhysicalLink: manualPhysicalLink ?? this.manualPhysicalLink,
    );
  }
}

/// Legacy alias for older call sites.
typedef StreamControllerBinding = StreamControllerElementMapping;

class StreamControllerMappingStore {
  static const _bindingsKey = 'stream.controller.bindings';

  StreamControllerMappingStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<StreamControllerMappingStore> load() async {
    return StreamControllerMappingStore(await SharedPreferences.getInstance());
  }

  List<StreamControllerElementMapping> get bindings {
    final raw = _prefs.getString(_bindingsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => StreamControllerElementMapping.fromJson(Map<String, dynamic>.from(entry)))
          .where((binding) => binding.sourceElementId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  StreamControllerElementMapping? mappingFor(String elementId) {
    for (final binding in bindings) {
      if (binding.sourceElementId == elementId) return binding;
    }
    return null;
  }

  Future<void> saveBindings(List<StreamControllerElementMapping> bindings) async {
    final payload = bindings.map((binding) => binding.toJson()).toList();
    await _prefs.setString(_bindingsKey, jsonEncode(payload));
  }

  Future<void> upsert(StreamControllerElementMapping mapping) async {
    final updated = [
      ...bindings.where((b) => b.sourceElementId != mapping.sourceElementId),
      mapping,
    ];
    await saveBindings(updated);
  }

  Future<void> removeForElement(String elementId) async {
    await saveBindings(
      bindings.where((b) => b.sourceElementId != elementId).toList(),
    );
  }

  String bindingsJson() => jsonEncode(bindings.map((binding) => binding.toJson()).toList());
}
