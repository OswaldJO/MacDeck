import '../models/stream_controller_element_mapping.dart';
import 'stream_controller_profile_store.dart';

export '../models/stream_controller_element_mapping.dart';

class StreamControllerMappingStore {
  static const bindingsKey = 'stream.controller.bindings';

  StreamControllerMappingStore(this._profiles);

  final StreamControllerProfileStore _profiles;

  StreamControllerProfileStore get profileStore => _profiles;

  static Future<StreamControllerMappingStore> load() async {
    final profiles = await StreamControllerProfileStore.load();
    return StreamControllerMappingStore(profiles);
  }

  List<StreamControllerProfile> get profiles => _profiles.profiles;

  String? get activeProfileId => _profiles.activeProfileId;

  List<StreamControllerElementMapping> get bindings => _profiles.activeBindings;

  StreamControllerElementMapping? mappingFor(String elementId) {
    for (final binding in bindings) {
      if (binding.sourceElementId == elementId) return binding;
    }
    return null;
  }

  Future<void> syncFromLegacyBindings() => _profiles.syncActiveFromLegacyBindings();

  Future<void> saveBindings(List<StreamControllerElementMapping> bindings) async {
    await _profiles.updateActiveBindings(bindings);
  }

  Future<void> upsert(StreamControllerElementMapping mapping) async {
    final updated = [
      ...bindings.where((b) => b.sourceElementId != mapping.sourceElementId),
      mapping,
    ];
    await saveBindings(updated);
  }

  Future<void> removeForElement(String elementId) async {
    await saveBindings(
      bindings.where((b) => b.sourceElementId != elementId).toList(),
    );
  }

  Future<String> createProfile({required String name, bool copyFromActive = true}) =>
      _profiles.createProfile(name: name, copyFromActive: copyFromActive);

  Future<void> renameProfile(String id, String name) => _profiles.renameProfile(id, name);

  Future<bool> deleteProfile(String id) => _profiles.deleteProfile(id);

  Future<void> activateProfile(String id) => _profiles.activateProfile(id);

  String bindingsJson() => _profiles.activeBindingsJson();
}
