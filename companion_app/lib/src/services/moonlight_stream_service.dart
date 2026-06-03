import 'dart:convert';

import 'certificate_codec.dart';
import 'pairing_crypto_store.dart';
import 'pairing_state_store.dart';
import 'streaming_host_settings.dart';
import 'sunshine_pairing_service.dart';

/// Builds Moonlight stream launch parameters for native decode (Android Game activity).
class MoonlightStreamService {
  MoonlightStreamService(this._settings, {SunshinePairingService? sunshine})
      : _sunshineFuture = sunshine != null
            ? Future.value(sunshine)
            : StreamingHostSettings.load().then((s) => SunshinePairingService(s));

  final StreamingHostSettings _settings;
  final Future<SunshinePairingService> _sunshineFuture;

  static const moonlightUniqueId = '0123456789ABCDEF';
  static const defaultDesktopAppId = 881448767;

  Future<StreamLaunchConfig?> buildLaunchConfig({
    required int width,
    required int height,
    required int fps,
  }) async {
    if (!_settings.isConfigured) return null;

    final stateStore = await PairingStateStore.load();
    if (!stateStore.isPaired(_settings.hostAddress)) return null;

    final serverCertPem = stateStore.serverCertPem(_settings.hostAddress);
    if (serverCertPem == null || serverCertPem.isEmpty) return null;

    final cryptoStore = await PairingCryptoStore.load();
    if (!cryptoStore.hasMaterial) return null;
    final material = await cryptoStore.loadOrCreate();

    final sunshine = await _sunshineFuture;
    if (!await sunshine.verifyPairedWithHost()) return null;

    final desktopApp = await sunshine.resolveDesktopApp();
    final appId = desktopApp?.appId ?? defaultDesktopAppId;
    final appName = desktopApp?.appName ?? 'Desktop';
    final httpsPort = await sunshine.fetchAdvertisedHttpsPort() ?? _settings.httpsPort;
    final serverCertDer = CertificateCodec.pemToDer(serverCertPem);

    return StreamLaunchConfig(
      hostAddress: _settings.hostAddress,
      httpPort: _settings.httpPort,
      httpsPort: httpsPort,
      appId: appId,
      appName: appName,
      pcName: stateStore.savedHostname(_settings.hostAddress) ?? _settings.hostAddress,
      uniqueId: moonlightUniqueId,
      width: width,
      height: height,
      fps: fps,
      clientCertPem: material.clientCertPem,
      clientKeyPem: material.privateKeyPem,
      serverCertDerBase64: base64Encode(serverCertDer),
    );
  }
}

class StreamLaunchConfig {
  const StreamLaunchConfig({
    required this.hostAddress,
    required this.httpPort,
    required this.httpsPort,
    required this.appId,
    required this.appName,
    required this.pcName,
    required this.uniqueId,
    required this.width,
    required this.height,
    required this.fps,
    required this.clientCertPem,
    required this.clientKeyPem,
    required this.serverCertDerBase64,
  });

  final String hostAddress;
  final int httpPort;
  final int httpsPort;
  final int appId;
  final String appName;
  final String pcName;
  final String uniqueId;
  final int width;
  final int height;
  final int fps;
  final String clientCertPem;
  final String clientKeyPem;
  final String serverCertDerBase64;

  Map<String, dynamic> toMethodChannelMap() {
    return {
      'hostAddress': hostAddress,
      'httpPort': httpPort,
      'httpsPort': httpsPort,
      'appId': appId,
      'appName': appName,
      'pcName': pcName,
      'uniqueId': uniqueId,
      'width': width,
      'height': height,
      'fps': fps,
      'clientCertPem': clientCertPem,
      'clientKeyPem': clientKeyPem,
      'serverCertDerBase64': serverCertDerBase64,
    };
  }
}

class StreamStartOutcome {
  const StreamStartOutcome._({required this.ok, this.message});

  final bool ok;
  final String? message;

  factory StreamStartOutcome.success([String? message]) =>
      StreamStartOutcome._(ok: true, message: message);

  factory StreamStartOutcome.failed(String message) =>
      StreamStartOutcome._(ok: false, message: message);
}
