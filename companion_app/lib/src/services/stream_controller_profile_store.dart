import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/stream_controller_element_mapping.dart';

/// Named set of gamepad → keyboard / Swap mappings.
class StreamControllerProfile {
  const StreamControllerProfile({
    required this.id,
    required this.name,
    required this.bindings,
    required this.updatedAtMs,
  });

  static const defaultProfileId = 'profile_default';

  final String id;
  final String name;
  final List<StreamControllerElementMapping> bindings;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bindings': bindings.map((b) => b.toJson()).toList(),
        'updatedAtMs': updatedAtMs,
      };

  factory StreamControllerProfile.fromJson(Map<String, dynamic> json) {
    final bindingsRaw = json['bindings'];
    final bindings = bindingsRaw is List
        ? bindingsRaw
            .whereType<Map>()
            .map((e) => StreamControllerElementMapping.fromJson(Map<String, dynamic>.from(e)))
            .where((b) => b.sourceElementId.isNotEmpty)
            .toList()
        : const <StreamControllerElementMapping>[];
    return StreamControllerProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Profile',
      bindings: bindings,
      updatedAtMs: json['updatedAtMs'] as int? ?? 0,
    );
  }

  StreamControllerProfile copyWith({
    String? name,
    List<StreamControllerElementMapping>? bindings,
    int? updatedAtMs,
  }) {
    return StreamControllerProfile(
      id: id,
      name: name ?? this.name,
      bindings: bindings ?? this.bindings,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  static StreamControllerProfile emptyDefault({String name = 'Default'}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return StreamControllerProfile(
      id: defaultProfileId,
      name: name,
      bindings: const [],
      updatedAtMs: now,
    );
  }
}

/// Persists named mapping profiles and keeps [StreamControllerMappingStore] bindings in sync.
class StreamControllerProfileStore {
  static const profilesKey = 'stream.controller.profiles.v1';
  static const activeIdKey = 'stream.controller.activeProfileId';
  static const legacyBindingsKey = 'stream.controller.bindings';

  StreamControllerProfileStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<StreamControllerProfileStore> load() async {
    final store = StreamControllerProfileStore(await SharedPreferences.getInstance());
    await store.ensureInitialized();
    return store;
  }

  List<StreamControllerProfile> get profiles => _readProfiles();

  String? get activeProfileId => _prefs.getString(activeIdKey);

  StreamControllerProfile? get activeProfile {
    final id = activeProfileId;
    if (id == null) return null;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return profiles.isNotEmpty ? profiles.first : null;
  }

  List<StreamControllerElementMapping> get activeBindings =>
      activeProfile?.bindings ?? const [];

  Future<void> ensureInitialized() async {
    if (_prefs.containsKey(profilesKey)) {
      await _repairActiveIdIfNeeded();
      return;
    }
    final legacy = _readLegacyBindings();
    final now = DateTime.now().millisecondsSinceEpoch;
    final initial = StreamControllerProfile(
      id: StreamControllerProfile.defaultProfileId,
      name: 'Default',
      bindings: legacy,
      updatedAtMs: now,
    );
    await _writeProfiles([initial]);
    await _prefs.setString(activeIdKey, initial.id);
    await _writeLegacyBindings(legacy);
  }

  Future<void> _repairActiveIdIfNeeded() async {
    final list = _readProfiles();
    if (list.isEmpty) {
      await _prefs.remove(profilesKey);
      await ensureInitialized();
      return;
    }
    final active = activeProfileId;
    if (active == null || !list.any((p) => p.id == active)) {
      await _prefs.setString(activeIdKey, list.first.id);
      await _writeLegacyBindings(list.first.bindings);
    }
  }

  /// After native overlay edits, merge legacy bindings into the active profile.
  Future<void> syncActiveFromLegacyBindings() async {
    final legacy = _readLegacyBindings();
    final active = activeProfile;
    if (active == null) return;
    if (_bindingsEqual(active.bindings, legacy)) return;
    await _updateProfileBindings(active.id, legacy);
  }

  Future<void> updateActiveBindings(List<StreamControllerElementMapping> bindings) async {
    final active = activeProfile;
    if (active == null) return;
    await _updateProfileBindings(active.id, bindings);
  }

  Future<String> createProfile({
    required String name,
    bool copyFromActive = true,
  }) async {
    final trimmed = name.trim();
    final profileName = trimmed.isEmpty ? 'New profile' : trimmed;
    final source = copyFromActive ? activeBindings : const <StreamControllerElementMapping>[];
    final profile = StreamControllerProfile(
      id: 'profile_${DateTime.now().microsecondsSinceEpoch}',
      name: profileName,
      bindings: List<StreamControllerElementMapping>.from(source),
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final updated = [...profiles, profile];
    await _writeProfiles(updated);
    return profile.id;
  }

  Future<void> renameProfile(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final updated = profiles
        .map(
          (p) => p.id == id
              ? p.copyWith(name: trimmed, updatedAtMs: DateTime.now().millisecondsSinceEpoch)
              : p,
        )
        .toList();
    await _writeProfiles(updated);
  }

  Future<bool> deleteProfile(String id) async {
    final list = profiles;
    if (list.length <= 1) return false;
    final wasActive = activeProfileId == id;
    final updated = list.where((p) => p.id != id).toList();
    await _writeProfiles(updated);
    if (wasActive) {
      await activateProfile(updated.first.id);
    }
    return true;
  }

  Future<void> activateProfile(String id) async {
    final profile = profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => profiles.first,
    );
    await _prefs.setString(activeIdKey, profile.id);
    await _writeLegacyBindings(profile.bindings);
  }

  String activeBindingsJson() =>
      jsonEncode(activeBindings.map((b) => b.toJson()).toList());

  List<StreamControllerElementMapping> _readLegacyBindings() {
    final raw = _prefs.getString(legacyBindingsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => StreamControllerElementMapping.fromJson(Map<String, dynamic>.from(e)))
          .where((b) => b.sourceElementId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<StreamControllerProfile> _readProfiles() {
    final raw = _prefs.getString(profilesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => StreamControllerProfile.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => p.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeProfiles(List<StreamControllerProfile> list) async {
    await _prefs.setString(
      profilesKey,
      jsonEncode(list.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _writeLegacyBindings(List<StreamControllerElementMapping> bindings) async {
    await _prefs.setString(
      legacyBindingsKey,
      jsonEncode(bindings.map((b) => b.toJson()).toList()),
    );
  }

  Future<void> _updateProfileBindings(
    String id,
    List<StreamControllerElementMapping> bindings,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = profiles
        .map(
          (p) => p.id == id
              ? p.copyWith(bindings: bindings, updatedAtMs: now)
              : p,
        )
        .toList();
    await _writeProfiles(updated);
    if (activeProfileId == id) {
      await _writeLegacyBindings(bindings);
    }
  }

  static bool _bindingsEqual(
    List<StreamControllerElementMapping> a,
    List<StreamControllerElementMapping> b,
  ) {
    if (a.length != b.length) return false;
    final byId = {for (final m in a) m.sourceElementId: m};
    for (final other in b) {
      final mine = byId[other.sourceElementId];
      if (mine == null) return false;
      if (mine.targetLabel != other.targetLabel) return false;
      if (mine.targetAction != other.targetAction) return false;
      if (mine.physicalKeyCode != other.physicalKeyCode) return false;
      if (mine.manualPhysicalLink != other.manualPhysicalLink) return false;
      if (!_codesEqual(mine.moonlightKeyCodes, other.moonlightKeyCodes)) return false;
    }
    return true;
  }

  static bool _codesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
