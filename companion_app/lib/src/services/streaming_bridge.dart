import 'dart:async';

import 'package:flutter/services.dart';

import '../models/host_info.dart';
import 'companion_device_identity.dart';
import 'pairing_cancellation.dart';
import 'playnite_host_client.dart';
import 'stream_controller_settings.dart';
import 'stream_touch_settings.dart';
import 'streaming_host_settings.dart';

/// Discovery, consent pairing, and native video via Playnite protocol.
class StreamingBridge {
  static const String channelName = 'com.playnite.companion/streaming_bridge';

  StreamingBridge({
    MethodChannel? channel,
    PlayniteHostClient? hostClient,
    StreamingHostSettings? settings,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _settingsFuture = settings != null
            ? Future.value(settings)
            : StreamingHostSettings.load(),
        _hostClientOverride = hostClient;

  final MethodChannel _channel;
  final Future<StreamingHostSettings> _settingsFuture;
  final PlayniteHostClient? _hostClientOverride;

  Future<PlayniteHostClient> _client() async {
    final override = _hostClientOverride;
    if (override != null) return override;
    final settings = await _settingsFuture;
    return PlayniteHostClient(settings);
  }

  Future<List<HostInfo>> discoverHosts() async {
    final client = await _client();
    return client.discoverHosts();
  }

  Future<List<ConnectedControllerInfo>> listConnectedControllers() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listConnectedControllers');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((entry) => ConnectedControllerInfo.fromMap(entry))
          .where((controller) => controller.id.isNotEmpty)
          .toList();
    } on PlatformException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<PairingOutcome> pairWithHost({
    required String hostId,
    void Function(String status)? onProgress,
    PairingCancellation? cancellation,
  }) async {
    final client = await _client();
    return client.requestPair(onProgress: onProgress, cancellation: cancellation);
  }

  Future<void> cancelPairing() async {
    final client = await _client();
    final deviceId = await CompanionDeviceIdentity.deviceId();
    await client.cancelPairRequest(deviceId);
  }

  Future<Map<String, dynamic>> getStreamSession() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getStreamSession');
      if (raw == null) return const {};
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return const {};
    }
  }

  Future<void> clearPendingExternalStopLog() async {
    try {
      await _channel.invokeMethod<void>('clearPendingExternalStopLog');
    } catch (_) {}
  }

  Future<bool> resumeStream() async {
    try {
      final resumed = await _channel.invokeMethod<bool>('resumeStream');
      return resumed == true;
    } catch (_) {
      return false;
    }
  }

  Future<GamepadButtonPress?> awaitGamepadButtonPress({int timeoutMs = 15000}) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'awaitGamepadButtonPress',
        {'timeoutMs': timeoutMs},
      );
      if (raw == null) return null;
      return GamepadButtonPress(
        keyCode: (raw['keyCode'] as num?)?.toInt() ?? 0,
        label: raw['label']?.toString() ?? 'Button',
        elementId: raw['elementId']?.toString(),
      );
    } on PlatformException {
      return null;
    }
  }

  Future<void> cancelGamepadButtonPress() async {
    try {
      await _channel.invokeMethod<void>('cancelGamepadButtonPress');
    } catch (_) {}
  }

  Future<StreamStartOutcome> startStream({
    required String hostId,
    required int width,
    required int height,
    required int fps,
    StreamControllerSettings? controllerSettings,
    StreamTouchSettings? touchSettings,
    String? controllerBindingsJson,
  }) async {
    final client = await _client();
    final outcome = await client.startStream(width: width, height: height, fps: fps);
    if (!outcome.ok || outcome.host == null || outcome.videoPort == null) {
      return outcome;
    }

    try {
      final touch = touchSettings ?? await StreamTouchSettings.load();
      final started = await _channel.invokeMethod<bool>('startStream', {
        'host': outcome.host,
        'videoPort': outcome.videoPort,
        'audioPort': outcome.audioPort ?? StreamingHostSettings.defaultAudioPort,
        'audioTcpPort': outcome.audioTcpPort ?? StreamingHostSettings.defaultAudioTcpPort,
        'inputPort': outcome.inputPort ?? StreamingHostSettings.defaultInputPort,
        'width': outcome.width ?? width,
        'height': outcome.height ?? height,
        'controllerBindingsJson': controllerBindingsJson ?? '',
        ...touch.toMethodChannelMap(),
      });
      if (started == true) {
        return outcome;
      }
      await client.stopStreamOnHost();
      return StreamStartOutcome.failed('Native video player failed to start.');
    } on PlatformException catch (e) {
      await client.stopStreamOnHost();
      return StreamStartOutcome.failed(e.message ?? 'Native stream error');
    }
  }

  /// Best-effort Mac teardown (notification Stop may have already called native HTTP stop).
  Future<void> updateSwapStickSensitivity(double sensitivity) async {
    try {
      await _channel.invokeMethod<void>('updateSwapStickSensitivity', {
        'swapStickSensitivity': sensitivity,
      });
    } catch (_) {}
  }

  Future<void> ensureHostStreamStopped() async {
    final client = await _client();
    await client.stopStreamOnHost();
  }

  /// Android: notification Stop and other native paths invoke [onStreamStoppedExternally].
  void installExternalStopListener(
    Future<void> Function({String? logPath}) onStopped,
  ) {
    _channel.setMethodCallHandler((call) {
      if (call.method == 'onStreamStoppedExternally') {
        String? logPath;
        final args = call.arguments;
        if (args is Map) {
          final raw = args['logPath'];
          if (raw is String && raw.isNotEmpty) {
            logPath = raw;
          }
        }
        // Synchronous handler — async handlers still make Android wait for the Future.
        scheduleMicrotask(() => unawaited(onStopped(logPath: logPath)));
      }
      return Future.value(null);
    });
  }

  /// Stops the Mac host and native player. On Android, returns a log file path if one was written.
  Future<String?> stopStream() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('stopStream');
      final path = raw?['logPath'];
      if (path is String && path.isNotEmpty) {
        return path;
      }
    } catch (_) {}
    return null;
  }
}

class GamepadButtonPress {
  const GamepadButtonPress({
    required this.keyCode,
    required this.label,
    this.elementId,
  });

  final int keyCode;
  final String label;
  final String? elementId;
}
