import 'package:basic_utils/basic_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persistent Moonlight-style client certificate and key (reused across pairings).
class PairingCryptoStore {
  PairingCryptoStore(this._prefs);

  static const _certKey = 'streaming.pairing.clientCertPem';
  static const _privateKeyKey = 'streaming.pairing.clientKeyPem';

  final SharedPreferences _prefs;

  static Future<PairingCryptoStore> load() async {
    return PairingCryptoStore(await SharedPreferences.getInstance());
  }

  String? get clientCertPem => _prefs.getString(_certKey);

  String? get clientKeyPem => _prefs.getString(_privateKeyKey);

  bool get hasMaterial =>
      (clientCertPem?.isNotEmpty ?? false) && (clientKeyPem?.isNotEmpty ?? false);

  /// Returns PEM with Unix line endings, matching Moonlight Android.
  Future<PairingClientMaterial> loadOrCreate() async {
    final existingCert = clientCertPem;
    final existingKey = clientKeyPem;
    if (existingCert != null &&
        existingKey != null &&
        existingCert.isNotEmpty &&
        existingKey.isNotEmpty) {
      return PairingClientMaterial(
        clientCertPem: _normalizePem(existingCert),
        privateKeyPem: existingKey,
      );
    }
    final material = _generateClientMaterial();
    await _prefs.setString(_certKey, material.clientCertPem);
    await _prefs.setString(_privateKeyKey, material.privateKeyPem);
    return material;
  }

  static PairingClientMaterial _generateClientMaterial() {
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      {'CN': 'NVIDIA GameStream Client'},
      privateKey,
      publicKey,
    );
    final pemCert = _normalizePem(
      X509Utils.generateSelfSignedCertificate(privateKey, csr, 3650),
    );
    return PairingClientMaterial(
      clientCertPem: pemCert,
      privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    );
  }

  /// Moonlight strips CR; Sunshine/OpenSSL expect Unix PEM on the wire.
  static String _normalizePem(String pem) {
    return pem.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }
}

class PairingClientMaterial {
  const PairingClientMaterial({
    required this.clientCertPem,
    required this.privateKeyPem,
  });

  final String clientCertPem;
  final String privateKeyPem;
}
