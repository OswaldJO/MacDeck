import 'package:flutter/services.dart';

import '../models/host_info.dart';
import 'streaming_host_settings.dart';
import 'sunshine_pairing_service.dart';

/// Discovery and pairing via Sunshine/Moonlight HTTP (Dart, shared on iOS + Android).
class StreamingBridge {
  static const String channelName = 'com.playnite.companion/streaming_bridge';

  StreamingBridge({
    MethodChannel? channel,
    SunshinePairingService? sunshine,
    StreamingHostSettings? settings,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _settingsFuture = settings != null
            ? Future.value(settings)
            : StreamingHostSettings.load(),
        _sunshineOverride = sunshine;

  final MethodChannel _channel;
  final Future<StreamingHostSettings> _settingsFuture;
  final SunshinePairingService? _sunshineOverride;

  Future<SunshinePairingService> _sunshine() async {
    final override = _sunshineOverride;
    if (override != null) {
      return override;
    }
    final settings = await _settingsFuture;
    return SunshinePairingService(settings);
  }

  Future<List<HostInfo>> discoverHosts() async {
    final sunshine = await _sunshine();
    return sunshine.discoverHosts();
  }

  Future<PairingOutcome> pairWithPin({
    required String hostId,
    required String pin,
    void Function(String status)? onProgress,
  }) async {
    final sunshine = await _sunshine();
    return sunshine.pair(pin: pin, onProgress: onProgress);
  }

  Future<bool> startStream({
    required String hostId,
    required int width,
    required int height,
    required int fps,
  }) async {
    final started = await _channel.invokeMethod<bool>('startStream', {
      'hostId': hostId,
      'width': width,
      'height': height,
      'fps': fps,
    });
    return started ?? false;
  }

  Future<void> stopStream() async {
    await _channel.invokeMethod<void>('stopStream');
  }
}
