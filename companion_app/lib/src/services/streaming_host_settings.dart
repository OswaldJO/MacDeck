import 'package:shared_preferences/shared_preferences.dart';

/// Persisted Sunshine host address and control-plane credentials (dev builds).
class StreamingHostSettings {
  static const _hostKey = 'streaming.host.address';
  static const _httpPortKey = 'streaming.host.httpPort';
  static const _httpsPortKey = 'streaming.host.httpsPort';
  static const _controlPortKey = 'streaming.host.controlPort';
  static const _userKey = 'streaming.host.username';
  static const _passKey = 'streaming.host.password';

  static const defaultHttpPort = 47989;
  static const defaultHttpsPort = 47984;
  static const defaultControlPort = 47990;

  final SharedPreferences _prefs;

  StreamingHostSettings(this._prefs);

  static Future<StreamingHostSettings> load() async {
    return StreamingHostSettings(await SharedPreferences.getInstance());
  }

  String get hostAddress => _prefs.getString(_hostKey) ?? '';

  int get httpPort => _prefs.getInt(_httpPortKey) ?? defaultHttpPort;

  int get httpsPort => _prefs.getInt(_httpsPortKey) ?? defaultHttpsPort;

  int get controlPort => _prefs.getInt(_controlPortKey) ?? defaultControlPort;

  String get username => _prefs.getString(_userKey) ?? '';

  String get password => _prefs.getString(_passKey) ?? '';

  Future<void> save({
    required String hostAddress,
    int? httpPort,
    int? httpsPort,
    int? controlPort,
    String? username,
    String? password,
  }) async {
    await _prefs.setString(_hostKey, hostAddress.trim());
    if (httpPort != null) await _prefs.setInt(_httpPortKey, httpPort);
    if (httpsPort != null) await _prefs.setInt(_httpsPortKey, httpsPort);
    if (controlPort != null) await _prefs.setInt(_controlPortKey, controlPort);
    if (username != null) await _prefs.setString(_userKey, username);
    if (password != null) await _prefs.setString(_passKey, password);
  }

  bool get isConfigured => hostAddress.isNotEmpty;

  Uri httpBase() => Uri(scheme: 'http', host: hostAddress, port: httpPort);

  Uri httpsBase() => Uri(scheme: 'https', host: hostAddress, port: httpsPort);
}
