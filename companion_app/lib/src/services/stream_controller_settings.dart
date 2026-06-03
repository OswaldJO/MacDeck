import 'package:shared_preferences/shared_preferences.dart';

/// Moonlight stream controller options (applied natively when a session starts).
class StreamControllerSettings {
  static const _multiControllerKey = 'stream.controller.multiController';
  static const _swapFaceButtonsKey = 'stream.controller.swapFaceButtons';
  static const _onScreenControlsKey = 'stream.controller.onScreenControls';
  static const _deadZoneKey = 'stream.controller.deadZone';
  static const _usbDriverKey = 'stream.controller.usbDriver';
  static const _bindAllUsbKey = 'stream.controller.bindAllUsb';
  static const _mouseEmulationKey = 'stream.controller.mouseEmulation';

  StreamControllerSettings(this._prefs);

  final SharedPreferences _prefs;

  static Future<StreamControllerSettings> load() async {
    return StreamControllerSettings(await SharedPreferences.getInstance());
  }

  bool get multiController => _prefs.getBool(_multiControllerKey) ?? true;

  bool get swapFaceButtons => _prefs.getBool(_swapFaceButtonsKey) ?? false;

  bool get onScreenControls => _prefs.getBool(_onScreenControlsKey) ?? false;

  int get deadZonePercent => _prefs.getInt(_deadZoneKey) ?? 7;

  /// Android: use Moonlight USB driver for USB-attached pads (e.g. USB-C telescopic).
  bool get usbDriver => _prefs.getBool(_usbDriverKey) ?? true;

  /// Android: claim USB devices Moonlight does not recognize by default.
  bool get bindAllUsb => _prefs.getBool(_bindAllUsbKey) ?? false;

  /// Android: send some stick/trigger input as mouse movement (legacy titles).
  bool get mouseEmulation => _prefs.getBool(_mouseEmulationKey) ?? true;

  Future<void> save({
    bool? multiController,
    bool? swapFaceButtons,
    bool? onScreenControls,
    int? deadZonePercent,
    bool? usbDriver,
    bool? bindAllUsb,
    bool? mouseEmulation,
  }) async {
    if (multiController != null) {
      await _prefs.setBool(_multiControllerKey, multiController);
    }
    if (swapFaceButtons != null) {
      await _prefs.setBool(_swapFaceButtonsKey, swapFaceButtons);
    }
    if (onScreenControls != null) {
      await _prefs.setBool(_onScreenControlsKey, onScreenControls);
    }
    if (deadZonePercent != null) {
      await _prefs.setInt(_deadZoneKey, deadZonePercent.clamp(0, 20));
    }
    if (usbDriver != null) {
      await _prefs.setBool(_usbDriverKey, usbDriver);
    }
    if (bindAllUsb != null) {
      await _prefs.setBool(_bindAllUsbKey, bindAllUsb);
    }
    if (mouseEmulation != null) {
      await _prefs.setBool(_mouseEmulationKey, mouseEmulation);
    }
  }

  Map<String, dynamic> toMethodChannelMap() {
    return {
      'multiController': multiController,
      'swapFaceButtons': swapFaceButtons,
      'onScreenControls': onScreenControls,
      'deadZonePercent': deadZonePercent,
      'usbDriver': usbDriver,
      'bindAllUsb': bindAllUsb,
      'mouseEmulation': mouseEmulation,
    };
  }
}

class ConnectedControllerInfo {
  const ConnectedControllerInfo({
    required this.id,
    required this.name,
    this.vendor,
  });

  final String id;
  final String name;
  final String? vendor;

  factory ConnectedControllerInfo.fromMap(Map<dynamic, dynamic> map) {
    return ConnectedControllerInfo(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Controller',
      vendor: map['vendor']?.toString(),
    );
  }
}
