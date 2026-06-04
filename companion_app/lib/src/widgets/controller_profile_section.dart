import 'package:flutter/material.dart';

import '../services/stream_controller_mapping_store.dart';
import '../services/stream_controller_profile_share.dart';
import '../services/stream_controller_profile_store.dart';

/// Profile picker and CRUD for controller mapping presets.
class ControllerProfileSection extends StatelessWidget {
  const ControllerProfileSection({
    super.key,
    required this.profiles,
    required this.activeProfileId,
    required this.onProfilesChanged,
  });

  final List<StreamControllerProfile> profiles;
  final String? activeProfileId;
  final Future<void> Function() onProfilesChanged;

  StreamControllerProfile? get _active {
    if (activeProfileId == null) return null;
    for (final p in profiles) {
      if (p.id == activeProfileId) return p;
    }
    return profiles.isNotEmpty ? profiles.first : null;
  }

  Future<void> _promptName(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String name) onSave,
  }) async {
    final controller = TextEditingController(text: initial);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Profile name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.pop(dialogContext, true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (saved != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    await onSave(name);
    if (context.mounted) {
      await onProfilesChanged();
    }
  }

  Future<void> _createProfile(BuildContext context) async {
    final controller = TextEditingController(text: 'New profile');
    var copyFromActive = true;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New profile'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Profile name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: copyFromActive,
                    onChanged: (value) {
                      setDialogState(() => copyFromActive = value ?? true);
                    },
                    title: const Text('Copy current mappings'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    final store = await StreamControllerMappingStore.load();
    final id = await store.createProfile(name: name, copyFromActive: copyFromActive);
    await store.activateProfile(id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created and loaded "$name"')),
      );
      await onProfilesChanged();
    }
  }

  Future<void> _renameProfile(BuildContext context, StreamControllerProfile profile) async {
    await _promptName(
      context,
      title: 'Rename profile',
      initial: profile.name,
      onSave: (name) async {
        final store = await StreamControllerMappingStore.load();
        await store.renameProfile(profile.id, name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Renamed to "$name"')),
          );
        }
      },
    );
  }

  Future<void> _deleteProfile(BuildContext context, StreamControllerProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete profile?'),
        content: Text('Remove "${profile.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final store = await StreamControllerMappingStore.load();
    final ok = await store.deleteProfile(profile.id);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keep at least one profile')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "${profile.name}"')),
    );
    await onProfilesChanged();
  }

  Future<void> _loadProfile(BuildContext context, String profileId) async {
    if (profileId == activeProfileId) return;
    final store = await StreamControllerMappingStore.load();
    await store.activateProfile(profileId);
    final name = store.profiles.firstWhere((p) => p.id == profileId).name;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded "$name"')),
      );
      await onProfilesChanged();
    }
  }

  Future<void> _exportProfile(BuildContext context) async {
    final profile = _active;
    if (profile == null) return;
    await StreamControllerProfileShare.exportActiveProfile(context, profile: profile);
  }

  Future<void> _importProfile(BuildContext context) async {
    final parsed = await StreamControllerProfileShare.pickAndParse(context);
    if (parsed == null || !context.mounted) return;

    final imported = parsed.profile;
    final mappedCount = imported.bindings.where((b) => b.hasMapping).length;
    final activeName = _active?.name ?? 'current profile';
    final nameController = TextEditingController(text: imported.name);

    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Import profile'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '$mappedCount mapped button${mappedCount == 1 ? '' : 's'} from '
                  '"${imported.name}".',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name for new profile',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Or replace mappings in the loaded profile (“$activeName”) without changing its name.',
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'replace'),
              child: const Text('Replace loaded'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'new'),
              child: const Text('Import as new'),
            ),
          ],
        );
      },
    );

    if (!context.mounted || choice == null) return;

    if (choice == 'replace') {
      await StreamControllerProfileShare.replaceActiveProfile(
        context,
        imported: imported,
      );
    } else {
      await StreamControllerProfileShare.importAsNewProfile(
        context,
        imported: imported,
        nameOverride: nameController.text,
      );
    }
    if (context.mounted) {
      await onProfilesChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    final mappedCount = active?.bindings.where((b) => b.hasMapping).length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Mapping profiles',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: () => _createProfile(context),
              icon: const Icon(Icons.add),
              tooltip: 'New profile',
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Save different button layouts. Export or import JSON to move profiles between phones. '
          'Edits auto-save to the loaded profile.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        if (profiles.isEmpty)
          const Text('No profiles yet.')
        else
          DropdownButtonFormField<String>(
            value: activeProfileId ?? profiles.first.id,
            decoration: const InputDecoration(
              labelText: 'Loaded profile',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final profile in profiles)
                DropdownMenuItem(
                  value: profile.id,
                  child: Text(profile.name),
                ),
            ],
            onChanged: (id) {
              if (id != null) _loadProfile(context, id);
            },
          ),
        if (active != null) ...[
          const SizedBox(height: 8),
          Text(
            '$mappedCount mapped button${mappedCount == 1 ? '' : 's'} in "${active.name}"',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: active == null ? null : () => _exportProfile(context),
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: const Text('Export'),
            ),
            OutlinedButton.icon(
              onPressed: () => _importProfile(context),
              icon: const Icon(Icons.download_outlined, size: 18),
              label: const Text('Import'),
            ),
            OutlinedButton.icon(
              onPressed: active == null ? null : () => _renameProfile(context, active),
              icon: const Icon(Icons.drive_file_rename_outline, size: 18),
              label: const Text('Rename'),
            ),
            OutlinedButton.icon(
              onPressed: profiles.length <= 1 || active == null
                  ? null
                  : () => _deleteProfile(context, active),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
