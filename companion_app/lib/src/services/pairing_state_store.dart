import 'package:shared_preferences/shared_preferences.dart';

/// Persists Sunshine/Moonlight pairing state per host (LAN IP).
class PairingStateStore {
  PairingStateStore(this._prefs);

  static const _pairedPrefix = 'streaming.paired.';
  static const _serverCertPrefix = 'streaming.serverCert.';
  static const _hostnamePrefix = 'streaming.hostname.';

  final SharedPreferences _prefs;

  static Future<PairingStateStore> load() async {
    return PairingStateStore(await SharedPreferences.getInstance());
  }

  bool isPaired(String hostAddress) {
    if (hostAddress.isEmpty) return false;
    return _prefs.getBool('$_pairedPrefix$hostAddress') ?? false;
  }

  String? serverCertPem(String hostAddress) {
    return _prefs.getString('$_serverCertPrefix$hostAddress');
  }

  String? savedHostname(String hostAddress) {
    return _prefs.getString('$_hostnamePrefix$hostAddress');
  }

  Future<void> markPaired(
    String hostAddress, {
    required String serverCertPem,
    String? hostname,
  }) async {
    await _prefs.setBool('$_pairedPrefix$hostAddress', true);
    await _prefs.setString('$_serverCertPrefix$hostAddress', serverCertPem);
    if (hostname != null && hostname.isNotEmpty) {
      await _prefs.setString('$_hostnamePrefix$hostAddress', hostname);
    }
  }

  Future<void> clear(String hostAddress) async {
    await _prefs.remove('$_pairedPrefix$hostAddress');
    await _prefs.remove('$_serverCertPrefix$hostAddress');
    await _prefs.remove('$_hostnamePrefix$hostAddress');
  }
}
