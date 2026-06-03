import 'package:flutter/services.dart';

import '../models/host_info.dart';
import 'moonlight_stream_service.dart';
import 'streaming_host_settings.dart';
import 'sunshine_pairing_service.dart';

/// Discovery and pairing via Sunshine/Moonlight HTTP (Dart, shared on iOS + Android).
class StreamingBridge {
  static const String channelName = 'com.playnite.companion/streaming_bridge';

  StreamingBridge({
    MethodChannel? channel,
    SunshinePairingService? sunshine,
    MoonlightStreamService? streamService,
    StreamingHostSettings? settings,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _settingsFuture = settings != null
            ? Future.value(settings)
            : StreamingHostSettings.load(),
        _sunshineOverride = sunshine,
        _streamServiceOverride = streamService;

  final MethodChannel _channel;
  final Future<StreamingHostSettings> _settingsFuture;
  final SunshinePairingService? _sunshineOverride;
  final MoonlightStreamService? _streamServiceOverride;

  Future<MoonlightStreamService> _streamService() async {
    final override = _streamServiceOverride;
    if (override != null) return override;
    final settings = await _settingsFuture;
    return MoonlightStreamService(settings);
  }

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

  Future<StreamStartOutcome> startStream({
    required String hostId,
    required int width,
    required int height,
    required int fps,
  }) async {
    final streamService = await _streamService();
    final config = await streamService.buildLaunchConfig(
      width: width,
      height: height,
      fps: fps,
    );
    if (config == null) {
      return StreamStartOutcome.failed(
        'Host not paired. Complete Pairing first, then refresh Hosts.',
      );
    }

    try {
      final started = await _channel.invokeMethod<bool>(
        'startStream',
        config.toMethodChannelMap(),
      );
      if (started != true) {
        return StreamStartOutcome.failed('Native stream failed to start.');
      }
      return StreamStartOutcome.success('Streaming Desktop…');
    } on PlatformException catch (e) {
      return StreamStartOutcome.failed(e.message ?? e.code);
    } catch (e) {
      return StreamStartOutcome.failed(e.toString());
    }
  }

  Future<void> stopStream() async {
    await _channel.invokeMethod<void>('stopStream');
  }
}
