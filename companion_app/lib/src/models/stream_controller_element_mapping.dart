import '../data/gamepad_elements.dart';
import '../data/gamepad_swap_toggle.dart';
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
    this.targetAction,
  });

  final String sourceElementId;
  final String sourceLabel;
  final List<int> moonlightKeyCodes;
  final String targetLabel;
  final int? physicalKeyCode;
  final bool manualPhysicalLink;
  /// When [kSwapToggleTargetAction], pressing the button toggles Swap mouse mode.
  final String? targetAction;

  bool get hasKeyboardMapping => moonlightKeyCodes.isNotEmpty;

  bool get isSwapToggleMapping => targetAction == kSwapToggleTargetAction;

  bool get hasMapping => hasKeyboardMapping || isSwapToggleMapping;

  Map<String, dynamic> toJson() => {
        'sourceElementId': sourceElementId,
        'sourceLabel': sourceLabel,
        'moonlightKeyCodes': moonlightKeyCodes,
        'targetLabel': targetLabel,
        if (physicalKeyCode != null) 'physicalKeyCode': physicalKeyCode,
        'manualPhysicalLink': manualPhysicalLink,
        if (targetAction != null) 'targetAction': targetAction,
      };

  factory StreamControllerElementMapping.fromJson(Map<String, dynamic> json) {
    final elementId = json['sourceElementId'] as String? ?? '';
    final element = gamepadElementById(elementId);
    final codes = _parseKeyCodes(json);
    final action = json['targetAction'] as String?;
    final label = json['targetLabel'] as String? ??
        (action == kSwapToggleTargetAction
            ? kSwapToggleTargetLabel
            : _labelForCodes(codes));
    return StreamControllerElementMapping(
      sourceElementId: elementId,
      sourceLabel: json['sourceLabel'] as String? ?? element?.label ?? elementId,
      moonlightKeyCodes: codes,
      targetLabel: label,
      physicalKeyCode: json['physicalKeyCode'] as int?,
      manualPhysicalLink: json['manualPhysicalLink'] as bool? ?? false,
      targetAction: action,
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
    String? targetAction,
    bool clearPhysicalKeyCode = false,
    bool clearTargetAction = false,
  }) {
    return StreamControllerElementMapping(
      sourceElementId: sourceElementId,
      sourceLabel: sourceLabel,
      moonlightKeyCodes: moonlightKeyCodes ?? this.moonlightKeyCodes,
      targetLabel: targetLabel ?? this.targetLabel,
      physicalKeyCode: clearPhysicalKeyCode ? null : (physicalKeyCode ?? this.physicalKeyCode),
      manualPhysicalLink: manualPhysicalLink ?? this.manualPhysicalLink,
      targetAction: clearTargetAction ? null : (targetAction ?? this.targetAction),
    );
  }
}

/// Legacy alias for older call sites.
typedef StreamControllerBinding = StreamControllerElementMapping;
