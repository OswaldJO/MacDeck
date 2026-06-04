import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/host_info.dart';
import 'companion_device_identity.dart';
import 'pairing_cancellation.dart';
import 'streaming_host_settings.dart';

/// Playnite-native LAN streaming client.
class PlayniteHostClient {
  PlayniteHostClient(this._settings);

  final StreamingHostSettings _settings;

  static const protocolVersion = 'playnite-stream/1';

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
        scheme: 'http',
        host: _settings.hostAddress,
        port: _settings.controlPort,
        path: path,
        queryParameters: query,
      );

  Future<Map<String, dynamic>?> fetchStatus() async {
    if (!_settings.isConfigured) return null;
    try {
      final response = await http.get(_uri('/playnite/v1/status')).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  Future<List<HostInfo>> discoverHosts() async {
    final status = await fetchStatus();
    if (status == null) return [];
    final deviceId = await CompanionDeviceIdentity.deviceId();
    final hostname = status['hostname'] as String? ?? _settings.hostAddress;
    final paired = await isDevicePaired(deviceId);
    return [
      HostInfo(
        id: _settings.hostAddress,
        name: hostname,
        address: _settings.hostAddress,
        paired: paired,
      ),
    ];
  }

  Future<bool> isDevicePaired(String deviceId) async {
    try {
      final response = await http.get(_uri('/playnite/v1/pair/clients')).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return false;
      final json = jsonDecode(response.body) as Map<String, dynamic>?;
      final devices = json?['devices'];
      if (devices is! List) return false;
      for (final entry in devices) {
        if (entry is Map && entry['id'] == deviceId) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String> pairStatus(String deviceId) async {
    try {
      final response = await http
          .get(_uri('/playnite/v1/pair/status', {'deviceId': deviceId}))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return 'unknown';
      final json = jsonDecode(response.body) as Map<String, dynamic>?;
      return json?['status'] as String? ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Withdraw a pending pairing request on the Mac (companion cancel).
  Future<void> cancelPairRequest(String deviceId) async {
    if (!_settings.isConfigured) return;
    try {
      await http
          .post(
            _uri('/playnite/v1/pair/cancel'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceId': deviceId}),
          )
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  /// Phone requests pairing; Mac user taps Pair or Deny.
  Future<PairingOutcome> requestPair({
    void Function(String status)? onProgress,
    PairingCancellation? cancellation,
  }) async {
    if (!_settings.isConfigured) {
      return PairingOutcome.failed('Add your Mac’s LAN IP on the Hosts tab first.');
    }

    final deviceId = await CompanionDeviceIdentity.deviceId();
    final deviceName = await CompanionDeviceIdentity.deviceName();

    try {
      onProgress?.call('Asking Mac to pair…');
      final begin = await http
          .post(
            _uri('/playnite/v1/pair/request'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceId': deviceId, 'deviceName': deviceName}),
          )
          .timeout(const Duration(seconds: 8));

      if (begin.statusCode != 200) {
        return PairingOutcome.failed('Mac rejected pairing (HTTP ${begin.statusCode}).');
      }
      final beginJson = jsonDecode(begin.body) as Map<String, dynamic>?;
      if (beginJson?['ok'] != true) {
        return PairingOutcome.failed(
          beginJson?['error'] as String? ?? 'Mac did not accept the pairing request.',
        );
      }

      if (cancellation?.isCancelled == true) {
        await cancelPairRequest(deviceId);
        return PairingOutcome.cancelled();
      }

      onProgress?.call('Waiting for approval on Mac…');
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (DateTime.now().isBefore(deadline)) {
        if (cancellation?.isCancelled == true) {
          await cancelPairRequest(deviceId);
          return PairingOutcome.cancelled();
        }
        final status = await pairStatus(deviceId);
        if (status == 'paired') {
          return PairingOutcome.success();
        }
        if (status == 'denied') {
          return PairingOutcome.failed('Mac denied pairing.');
        }
        await Future<void>.delayed(const Duration(seconds: 1));
        if (cancellation?.isCancelled == true) {
          await cancelPairRequest(deviceId);
          return PairingOutcome.cancelled();
        }
      }
      return PairingOutcome.failed('Timed out waiting for Mac to approve pairing.');
    } catch (e) {
      return PairingOutcome.failed('Could not reach Mac: $e');
    }
  }

  Future<StreamStartOutcome> startStream({
    required int width,
    required int height,
    required int fps,
  }) async {
    final deviceId = await CompanionDeviceIdentity.deviceId();
    if (!await isDevicePaired(deviceId)) {
      return StreamStartOutcome.failed('Not paired with this Mac.');
    }

    try {
      final response = await http
          .post(
            _uri('/playnite/v1/stream/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': deviceId,
              'width': width,
              'height': height,
              'fps': fps,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return StreamStartOutcome.failed('Mac could not start stream (HTTP ${response.statusCode}).');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>?;
      if (json?['ok'] != true) {
        return StreamStartOutcome.failed(json?['error'] as String? ?? 'Stream start failed.');
      }
      final host = json?['host'] as String? ?? _settings.hostAddress;
      final videoPort = json?['videoPort'] as int? ?? StreamingHostSettings.defaultVideoPort;
      final audioPort = json?['audioPort'] as int? ?? StreamingHostSettings.defaultAudioPort;
      final audioTcpPort = json?['audioTcpPort'] as int? ?? StreamingHostSettings.defaultAudioTcpPort;
      final inputPort = json?['inputPort'] as int? ?? StreamingHostSettings.defaultInputPort;
      return StreamStartOutcome.success(
        host: host,
        videoPort: videoPort,
        audioPort: audioPort,
        audioTcpPort: audioTcpPort,
        inputPort: inputPort,
        width: width,
        height: height,
      );
    } catch (e) {
      return StreamStartOutcome.failed('Could not start stream: $e');
    }
  }

  Future<void> stopStreamOnHost() async {
    try {
      await http.post(_uri('/playnite/v1/stream/stop')).timeout(const Duration(seconds: 4));
    } catch (_) {}
  }
}

class PairingOutcome {
  const PairingOutcome._({required this.ok, this.message, this.cancelled = false});

  final bool ok;
  final String? message;
  final bool cancelled;

  factory PairingOutcome.success() => const PairingOutcome._(ok: true);

  factory PairingOutcome.failed(String message) => PairingOutcome._(ok: false, message: message);

  factory PairingOutcome.cancelled() => const PairingOutcome._(ok: false, cancelled: true);
}

class StreamStartOutcome {
  const StreamStartOutcome._({
    required this.ok,
    this.message,
    this.host,
    this.videoPort,
    this.audioPort,
    this.audioTcpPort,
    this.inputPort,
    this.width,
    this.height,
  });

  final bool ok;
  final String? message;
  final String? host;
  final int? videoPort;
  final int? audioPort;
  final int? audioTcpPort;
  final int? inputPort;
  final int? width;
  final int? height;

  factory StreamStartOutcome.success({
    required String host,
    required int videoPort,
    required int audioPort,
    required int audioTcpPort,
    required int inputPort,
    required int width,
    required int height,
  }) =>
      StreamStartOutcome._(
        ok: true,
        host: host,
        videoPort: videoPort,
        audioPort: audioPort,
        audioTcpPort: audioTcpPort,
        inputPort: inputPort,
        width: width,
        height: height,
      );

  factory StreamStartOutcome.failed(String message) => StreamStartOutcome._(ok: false, message: message);
}
