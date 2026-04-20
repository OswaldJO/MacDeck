import 'package:flutter/services.dart';

import '../models/host_info.dart';

/// Native bridge for discovery, PIN pairing, and streaming session control.
///
/// Implementations live in:
/// - Android: `MainActivity.kt` (`MethodChannel`)
/// - iOS: `AppDelegate.swift` (`FlutterMethodChannel`)
class StreamingBridge {
  static const String channelName = 'com.playnite.companion/streaming_bridge';

  StreamingBridge({MethodChannel? channel})
      : _channel = channel ?? MethodChannel(StreamingBridge.channelName);

  final MethodChannel _channel;

  Future<List<HostInfo>> discoverHosts() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('discoverHosts');
    final list = raw ?? <dynamic>[];
    return list.map((entry) {
      final map = Map<dynamic, dynamic>.from(entry as Map<dynamic, dynamic>);
      return HostInfo.fromMap(map);
    }).toList();
  }

  Future<bool> pairWithPin({
    required String hostId,
    required String pin,
  }) async {
    final paired = await _channel.invokeMethod<bool>('pairWithPin', {
      'hostId': hostId,
      'pin': pin,
    });
    return paired ?? false;
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
