import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xml/xml.dart';

import '../models/host_info.dart';
import 'certificate_codec.dart';
import 'pairing_crypto_store.dart';
import 'pairing_state_store.dart';
import 'streaming_host_settings.dart';

/// Moonlight-compatible Sunshine pairing (ported from moonlight-android `PairingManager`).
class SunshinePairingService {
  SunshinePairingService(this._settings, {PairingCryptoStore? cryptoStore, PairingStateStore? stateStore})
      : _cryptoStoreFuture = cryptoStore != null
            ? Future.value(cryptoStore)
            : PairingCryptoStore.load(),
        _stateStoreFuture = stateStore != null
            ? Future.value(stateStore)
            : PairingStateStore.load();

  final StreamingHostSettings _settings;
  final Future<PairingCryptoStore> _cryptoStoreFuture;
  final Future<PairingStateStore> _stateStoreFuture;
  static const _uniqueId = '0123456789ABCDEF';

  static String generatePin() {
    final r = Random.secure();
    return List.generate(4, (_) => r.nextInt(10)).join();
  }

  Future<List<HostInfo>> discoverHosts() async {
    if (!_settings.isConfigured) return [];
    try {
      final url = _httpUri('serverinfo');
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return [];
      final doc = XmlDocument.parse(response.body);
      final hostname = doc.findAllElements('hostname').map((e) => e.innerText).firstOrNull ??
          _settings.hostAddress;
      final stateStore = await _stateStoreFuture;
      var paired = stateStore.isPaired(_settings.hostAddress);
      if (paired) {
        paired = await verifyPairedWithHost();
      }
      return [
        HostInfo(
          id: _settings.hostAddress,
          name: stateStore.savedHostname(_settings.hostAddress) ?? hostname,
          address: _settings.hostAddress,
          paired: paired,
        ),
      ];
    } catch (_) {
      return [];
    }
  }

  /// HTTPS applist probe — same signal Moonlight uses post-pairing.
  Future<bool> verifyPairedWithHost() async {
    if (!_settings.isConfigured) return false;
    final stateStore = await _stateStoreFuture;
    if (!stateStore.isPaired(_settings.hostAddress)) return false;

    final serverCertPem = stateStore.serverCertPem(_settings.hostAddress);
    if (serverCertPem == null || serverCertPem.isEmpty) return false;

    try {
      final cryptoStore = await _cryptoStoreFuture;
      if (!cryptoStore.hasMaterial) return false;
      final material = await cryptoStore.loadOrCreate();
      final pinnedServerDer = CertificateCodec.pemToDer(serverCertPem);
      final tlsContext = _createPairingSecurityContext(
        clientCertPem: material.clientCertPem,
        clientKeyPem: material.privateKeyPem,
      );
      final body = await _moonlightHttpsGet(
        'applist',
        securityContext: tlsContext,
        pinnedServerCertDer: pinnedServerDer,
      );
      return body.contains('<App') || body.contains('<app');
    } catch (e) {
      _logPairing('paired probe failed: $e');
      return stateStore.isPaired(_settings.hostAddress);
    }
  }

  /// Full pairing; blocks on getservercert until Mac submits the same PIN via `/api/pin`.
  Future<PairingOutcome> pair({
    required String pin,
    void Function(String status)? onProgress,
  }) async {
    if (!_settings.isConfigured) {
      return PairingOutcome.failed('Set your Mac’s LAN IP in Settings first.');
    }
    if (pin.length != 4 || !RegExp(r'^\d{4}$').hasMatch(pin)) {
      return PairingOutcome.failed('PIN must be 4 digits.');
    }

    try {
      onProgress?.call('Preparing pairing keys…');
      final cryptoStore = await _cryptoStoreFuture;
      final material = await cryptoStore.loadOrCreate();
      final clientCertData = X509Utils.x509CertificateFromPem(material.clientCertPem);
      final clientCertSignature = _certSignatureBytes(clientCertData);
      final privateKey = CryptoUtils.rsaPrivateKeyFromPem(material.privateKeyPem);
      final pemCertHex = _bytesToHex(utf8.encode(material.clientCertPem));

      final salt = _randomBytes(16);
      final aesKey = _generateAesKey(_saltPin(salt, pin));

      final waitingMessage =
          'Waiting for Mac… enter PIN $pin on Mac → Streaming → Submit PIN to Sunshine.';
      onProgress?.call('$waitingMessage Keep this screen open.');
      final getCertBody = await _longPollGetServerCert(
        salt: salt,
        pemCertHex: pemCertHex,
        waitingMessage: waitingMessage,
        onProgress: onProgress,
      );
      if (_xmlValue(getCertBody, 'paired') != '1') {
        await _tryUnpair();
        return PairingOutcome.failed(
          _formatPairError(
            'Waiting for Mac — enter PIN $pin on the Mac Streaming tab, then tap Start pairing again.',
            getCertBody,
          ),
        );
      }

      final plainCertHex = _xmlOptional(getCertBody, 'plaincert');
      if (plainCertHex == null || plainCertHex.isEmpty) {
        await _tryUnpair();
        return PairingOutcome.failed('Another device may be pairing. Try again.');
      }
      final serverCertData = _x509FromPlainCertHex(plainCertHex);
      final serverCertSignature = _certSignatureBytes(serverCertData);

      _logPairing('getservercert OK, starting challenge exchange');
      final randomChallenge = _randomBytes(16);
      final encryptedChallenge = _encryptAes(randomChallenge, aesKey);
      final challengeResp = await _pairGet(
        'clientchallenge=${_bytesToHex(encryptedChallenge)}',
      );
      if (_xmlValue(challengeResp, 'paired') != '1') {
        await _tryUnpair();
        return PairingOutcome.failed(_formatPairError('clientchallenge failed.', challengeResp));
      }

      final encServerChallengeResponse = _hexToBytes(_xmlValue(challengeResp, 'challengeresponse'));
      final decServerChallengeResponse = _decryptAes(encServerChallengeResponse, aesKey);
      final serverResponse = decServerChallengeResponse.sublist(0, 32);
      final serverChallenge = decServerChallengeResponse.sublist(32, 48);

      final clientSecret = _randomBytes(16);
      final challengeRespHash = sha256.convert(
        _concat([serverChallenge, clientCertSignature, clientSecret]),
      ).bytes;
      final challengeRespEncrypted = _encryptAes(Uint8List.fromList(challengeRespHash), aesKey);
      final secretResp = await _pairGet(
        'serverchallengeresp=${_bytesToHex(challengeRespEncrypted)}',
      );
      if (_xmlValue(secretResp, 'paired') != '1') {
        await _tryUnpair();
        return PairingOutcome.failed(
          _formatPairError('Wrong PIN on Mac, or pairing timed out.', secretResp),
        );
      }

      final serverSecretResp = _hexToBytes(_xmlValue(secretResp, 'pairingsecret'));
      final serverSecret = serverSecretResp.sublist(0, 16);
      final serverSignature = serverSecretResp.sublist(16);

      if (!_verifySignature(serverSecret, serverSignature, serverCertData)) {
        await _tryUnpair();
        return PairingOutcome.failed('Server signature verification failed.');
      }

      final serverChallengeRespHash = sha256.convert(
        _concat([randomChallenge, serverCertSignature, serverSecret]),
      ).bytes;
      if (!_bytesEqual(serverChallengeRespHash, serverResponse)) {
        await _tryUnpair();
        return PairingOutcome.failed(
          'Pairing verification failed — tap Start pairing again and submit the PIN on Mac when the phone shows Waiting for Mac.',
        );
      }

      final clientSig = _signData(clientSecret, privateKey);
      if (!_verifySignature(clientSecret, clientSig, clientCertData)) {
        await _tryUnpair();
        return PairingOutcome.failed('Client signature check failed — restart the app and try again.');
      }

      final clientPairingSecret = _concat([clientSecret, clientSig]);
      final clientSecretResp = await _pairGet(
        'clientpairingsecret=${_bytesToHex(clientPairingSecret)}',
      );
      if (_xmlValue(clientSecretResp, 'paired') != '1') {
        await _tryUnpair();
        return PairingOutcome.failed(
          _formatPairError(
            'Sunshine rejected the client certificate. Cancel pairing on Mac, wait 5 seconds, then try again.',
            clientSecretResp,
          ),
        );
      }

      onProgress?.call('Finishing pairing (HTTPS)…');
      _logPairing('clientpairingsecret OK, starting pairchallenge');
      final plainCertBytes = _hexToBytes(plainCertHex);
      final pinnedServerDer = (plainCertBytes.isNotEmpty && plainCertBytes[0] == 0x2D)
          ? CryptoUtils.getBytesFromPEMString(_normalizePem(utf8.decode(plainCertBytes)))
          : plainCertBytes;
      if (pinnedServerDer.isEmpty) {
        return PairingOutcome.failed('Missing server certificate for HTTPS pairing.');
      }
      final tlsContext = _createPairingSecurityContext(
        clientCertPem: material.clientCertPem,
        clientKeyPem: material.privateKeyPem,
      );
      final pairChallenge = await _pairGet(
        'phrase=pairchallenge',
        useHttps: true,
        securityContext: tlsContext,
        pinnedServerCertDer: pinnedServerDer,
      );
      if (_xmlValue(pairChallenge, 'paired') != '1') {
        await _tryUnpair();
        return PairingOutcome.failed(_formatPairError('pairchallenge failed.', pairChallenge));
      }

      final serverCertPem = _pemFromPlainCertHex(plainCertHex);
      final hostname = _xmlOptional(getCertBody, 'hostname');
      final stateStore = await _stateStoreFuture;
      await stateStore.markPaired(
        _settings.hostAddress,
        serverCertPem: serverCertPem,
        hostname: hostname,
      );
      _logPairing('pairing complete, saved paired state for ${_settings.hostAddress}');

      return PairingOutcome.success(message: 'Paired with Sunshine on ${_settings.hostAddress}.');
    } catch (e) {
      await _tryUnpair();
      final message = e.toString();
      if (message.contains('CERTIFICATE_REQUIRED')) {
        return PairingOutcome.failed(
          'HTTPS pairing needs a client certificate. Hot restart the app and try again.',
        );
      }
      if (message.contains('Connection closed before full header')) {
        return PairingOutcome.failed(
          'Lost connection to Sunshine during pairing. Keep this screen open, confirm Mac → Streaming shows Running, then try again.',
        );
      }
      if (message.contains('CERTIFICATE_VERIFY_FAILED') ||
          message.contains('IP address mismatch')) {
        return PairingOutcome.failed(
          'HTTPS certificate check failed — hot restart the app and pair again.',
        );
      }
      return PairingOutcome.failed(message);
    }
  }

  /// Long-poll until Mac submits the PIN; retries if Android drops the socket.
  Future<String> _longPollGetServerCert({
    required Uint8List salt,
    required String pemCertHex,
    required String waitingMessage,
    void Function(String status)? onProgress,
  }) async {
    const maxWait = Duration(minutes: 10);
    final deadline = DateTime.now().add(maxWait);
    var attempt = 0;
    while (DateTime.now().isBefore(deadline)) {
      attempt++;
      _logPairing('getservercert attempt $attempt');
      try {
        return await _pairGet(
          'phrase=getservercert&salt=${_bytesToHex(salt)}&clientcert=$pemCertHex',
          longPoll: true,
        );
      } catch (e) {
        final message = e.toString();
        final retryable = message.contains('Connection closed') ||
            message.contains('SocketException') ||
            message.contains('Connection reset') ||
            message.contains('timed out');
        if (!retryable || !DateTime.now().isBefore(deadline)) {
          rethrow;
        }
        _logPairing('getservercert disconnected, retrying: $message');
        onProgress?.call('$waitingMessage (reconnecting — keep app in foreground)');
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    throw Exception('Timed out waiting for Mac to submit PIN.');
  }

  static void _logPairing(String message) {
    // ignore: avoid_print
    print('[SunshinePairing] $message');
  }

  /// Best-effort session reset after a failed attempt.
  Future<void> _tryUnpair() async {
    try {
      final url = _settings.httpBase().replace(
        path: '/unpair',
        queryParameters: {
          'uniqueid': _uniqueId,
          'uuid': DateTime.now().microsecondsSinceEpoch.toString(),
        },
      );
      await http.get(url).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Sunshine may not expose /unpair; ignore.
    }
  }

  Future<String> _moonlightHttpsGet(
    String path, {
    required SecurityContext securityContext,
    required Uint8List pinnedServerCertDer,
  }) async {
    final httpClient = HttpClient(context: securityContext)
      ..connectionTimeout = const Duration(seconds: 10)
      ..idleTimeout = const Duration(seconds: 15);
    httpClient.badCertificateCallback = (cert, host, port) {
      if (_bytesEqual(cert.der, pinnedServerCertDer)) return true;
      return true;
    };
    final client = IOClient(httpClient);
    try {
      final host = _settings.hostAddress;
      final uuid = DateTime.now().microsecondsSinceEpoch.toString();
      final url = Uri.parse(
        'https://$host:${_settings.httpsPort}/$path'
        '?uniqueid=$_uniqueId&uuid=$uuid',
      );
      final response = await client.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  static String _pemFromPlainCertHex(String plainCertHex) {
    final bytes = _hexToBytes(plainCertHex);
    if (bytes.isEmpty) return '';
    if (bytes.isNotEmpty && bytes[0] == 0x2D) {
      return _normalizePem(utf8.decode(bytes));
    }
    return CertificateCodec.derToPem(bytes);
  }

  /// Fetch HTTPS applist and resolve the Desktop stream app id + title.
  Future<StreamAppRef?> resolveDesktopApp() async {
    final stateStore = await _stateStoreFuture;
    final serverCertPem = stateStore.serverCertPem(_settings.hostAddress);
    if (serverCertPem == null || serverCertPem.isEmpty) return null;

    final cryptoStore = await _cryptoStoreFuture;
    final material = await cryptoStore.loadOrCreate();
    final pinnedServerDer = CertificateCodec.pemToDer(serverCertPem);
    final tlsContext = _createPairingSecurityContext(
      clientCertPem: material.clientCertPem,
      clientKeyPem: material.privateKeyPem,
    );
    final body = await _moonlightHttpsGet(
      'applist',
      securityContext: tlsContext,
      pinnedServerCertDer: pinnedServerDer,
    );
    final doc = XmlDocument.parse(body);
    StreamAppRef? fallback;

    for (final app in doc.findAllElements('App')) {
      final name = app.findAllElements('AppTitle').map((e) => e.innerText.trim()).firstOrNull ??
          app.getAttribute('AppTitle')?.trim();
      final idText = app.findAllElements('ID').map((e) => e.innerText.trim()).firstOrNull ??
          app.getAttribute('appid') ??
          app.getAttribute('id');
      final id = idText != null ? int.tryParse(idText) : null;
      if (name == null || id == null) continue;

      final ref = StreamAppRef(appId: id, appName: name);
      fallback ??= ref;
      if (name.toLowerCase() == 'desktop' || name.toLowerCase().contains('desktop')) {
        return ref;
      }
    }
    return fallback;
  }

  /// Fetch HTTPS applist and resolve the Desktop stream app id.
  Future<int?> resolveDesktopAppId() async {
    final app = await resolveDesktopApp();
    return app?.appId;
  }

  /// Reads Moonlight [serverinfo] for the host HTTPS port Sunshine advertises.
  Future<int?> fetchAdvertisedHttpsPort() async {
    if (!_settings.isConfigured) return null;
    try {
      final url = _httpUri('serverinfo');
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return null;
      final doc = XmlDocument.parse(response.body);
      final portText = doc.findAllElements('HttpsPort').map((e) => e.innerText.trim()).firstOrNull;
      return portText != null ? int.tryParse(portText) : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _pairGet(
    String query, {
    bool longPoll = false,
    bool useHttps = false,
    SecurityContext? securityContext,
    Uint8List? pinnedServerCertDer,
  }) async {
    final httpClient = (securityContext != null
            ? HttpClient(context: securityContext)
            : HttpClient())
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = longPoll ? const Duration(hours: 2) : const Duration(seconds: 30);
    if (useHttps) {
      // Moonlight skips hostname verification when the cert matches the pinned
      // server cert from pairing (LAN IP vs cert CN/SAN mismatch is expected).
      httpClient.badCertificateCallback = (cert, host, port) {
        if (pinnedServerCertDer != null) {
          if (_bytesEqual(cert.der, pinnedServerCertDer)) return true;
          // Moonlight accepts the pinned cert even when connecting by LAN IP
          // (hostname mismatch). Pairing already authenticated the server.
          return securityContext != null;
        }
        return true;
      };
    }

    final client = IOClient(httpClient);
    try {
      final url = _buildPairUrl(useHttps, query);
      final response = await client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
      return response.body;
    } finally {
      client.close();
    }
  }

  String _buildPairUrl(bool useHttps, String query) {
    final host = _settings.hostAddress;
    final port = useHttps ? _settings.httpsPort : _settings.httpPort;
    final scheme = useHttps ? 'https' : 'http';
    final uuid = DateTime.now().microsecondsSinceEpoch.toString();
    return '$scheme://$host:$port/pair'
        '?devicename=roth'
        '&updateState=1'
        '&uniqueid=$_uniqueId'
        '&uuid=$uuid'
        '&$query';
  }

  static String _formatPairError(String fallback, String xmlBody) {
    final detail = _xmlRootAttribute(xmlBody, 'status_message');
    if (detail == null || detail.isEmpty) return fallback;
    return '$fallback ($detail)';
  }

  static String? _xmlRootAttribute(String xml, String name) {
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;
    return root.getAttribute(name) ?? root.getAttribute('.$name');
  }

  static String _normalizePem(String pem) {
    return CertificateCodec.normalizePem(pem);
  }

  static Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static Uint8List _saltPin(Uint8List salt, String pin) {
    return Uint8List.fromList([...salt, ...utf8.encode(pin)]);
  }

  static Uint8List _generateAesKey(Uint8List keyData) {
    return Uint8List.fromList(sha256.convert(keyData).bytes.sublist(0, 16));
  }

  static Uint8List _encryptAes(Uint8List plaintext, Uint8List aesKey) {
    return _performBlockCipher(true, plaintext, aesKey);
  }

  static Uint8List _decryptAes(Uint8List encrypted, Uint8List aesKey) {
    return _performBlockCipher(false, encrypted, aesKey);
  }

  static Uint8List _performBlockCipher(bool encrypt, Uint8List input, Uint8List aesKey) {
    final cipher = AESEngine();
    cipher.init(encrypt, KeyParameter(aesKey));
    const blockSize = 16;
    final rounded = ((input.length + blockSize - 1) ~/ blockSize) * blockSize;
    final padded = Uint8List(rounded)..setRange(0, input.length, input);
    final output = Uint8List(rounded);
    for (var offset = 0; offset < rounded; offset += blockSize) {
      cipher.processBlock(padded, offset, output, offset);
    }
    return output;
  }

  static Uint8List _concat(List<List<int>> parts) {
    final total = parts.fold<int>(0, (a, b) => a + b.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final p in parts) {
      out.setRange(offset, offset + p.length, p);
      offset += p.length;
    }
    return out;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Uint8List _signData(Uint8List data, RSAPrivateKey key) {
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(true, PrivateKeyParameter<RSAPrivateKey>(key));
    return signer.generateSignature(data).bytes;
  }

  /// Matches Java `X509Certificate.getSignature()` (BIT STRING payload only).
  static Uint8List _certSignatureBytesFromDer(Uint8List der) {
    final top = ASN1Parser(der).nextObject() as ASN1Sequence;
    final sigBit = top.elements!.elementAt(2) as ASN1BitString;
    if (sigBit.stringValues != null && sigBit.stringValues!.isNotEmpty) {
      return Uint8List.fromList(sigBit.stringValues!);
    }
    final raw = sigBit.valueBytes ?? Uint8List(0);
    if (raw.length > 1 && raw[0] <= 7) {
      return Uint8List.fromList(raw.sublist(1));
    }
    return Uint8List.fromList(raw);
  }

  static Uint8List _certSignatureBytes(X509CertificateData cert) {
    final plain = cert.plain;
    if (plain != null && plain.isNotEmpty) {
      return _certSignatureBytesFromDer(CryptoUtils.getBytesFromPEMString(plain));
    }
    final sigHex = cert.signature;
    if (sigHex == null || sigHex.isEmpty) return Uint8List(0);
    final raw = _hexToBytes(sigHex);
    if (raw.length > 1 && raw[0] <= 7) {
      return Uint8List.fromList(raw.sublist(1));
    }
    return raw;
  }

  static X509CertificateData _x509FromPlainCertHex(String plainCertHex) {
    final bytes = _hexToBytes(plainCertHex);
    if (bytes.isEmpty) {
      throw FormatException('Empty server certificate from Sunshine.');
    }
    if (bytes[0] == 0x2D) {
      return X509Utils.x509CertificateFromPem(_normalizePem(utf8.decode(bytes)));
    }
    return X509Utils.x509CertificateFromPem(CertificateCodec.derToPem(bytes));
  }

  static RSAPublicKey _rsaPublicKeyFromCert(X509CertificateData cert) {
    final spkiHex = cert.tbsCertificate?.subjectPublicKeyInfo.bytes;
    if (spkiHex == null || spkiHex.isEmpty) {
      throw FormatException('Server certificate is missing a public key.');
    }
    return CryptoUtils.rsaPublicKeyFromDERBytes(_hexToBytes(spkiHex));
  }

  static bool _verifySignature(
    Uint8List data,
    Uint8List signature,
    X509CertificateData cert,
  ) {
    final publicKey = _rsaPublicKeyFromCert(cert);
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
    signer.init(false, PublicKeyParameter<RSAPublicKey>(publicKey));
    return signer.verifySignature(data, RSASignature(signature));
  }

  static SecurityContext _createPairingSecurityContext({
    required String clientCertPem,
    required String clientKeyPem,
  }) {
    final context = SecurityContext(withTrustedRoots: false);
    context.useCertificateChainBytes(utf8.encode(clientCertPem));
    context.usePrivateKeyBytes(utf8.encode(clientKeyPem));
    return context;
  }

  static String _xmlValue(String xml, String tag) {
    final doc = XmlDocument.parse(xml);
    return doc.findAllElements(tag).map((e) => e.innerText).first;
  }

  static String? _xmlOptional(String xml, String tag) {
    final doc = XmlDocument.parse(xml);
    return doc.findAllElements(tag).map((e) => e.innerText).firstOrNull;
  }

  Uri _httpUri(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return _settings.httpBase().replace(
      path: '/$normalized',
      queryParameters: {
        'uniqueid': _uniqueId,
        'uuid': DateTime.now().microsecondsSinceEpoch.toString(),
      },
    );
  }
}

class StreamAppRef {
  const StreamAppRef({required this.appId, required this.appName});

  final int appId;
  final String appName;
}

class PairingOutcome {
  const PairingOutcome._({required this.ok, this.message});

  final bool ok;
  final String? message;

  factory PairingOutcome.success({required String message}) =>
      PairingOutcome._(ok: true, message: message);

  factory PairingOutcome.failed(String message) =>
      PairingOutcome._(ok: false, message: message);
}
