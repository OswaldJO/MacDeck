import 'dart:async';

import 'package:flutter/material.dart';

import '../models/stream_shortcut.dart';
import '../services/stream_shortcuts_store.dart';
import 'keyboard_chord_editor_sheet.dart';

/// Settings list: create, edit, and delete stream keyboard shortcuts.
class StreamShortcutsSection extends StatefulWidget {
  const StreamShortcutsSection({super.key});

  @override
  State<StreamShortcutsSection> createState() => _StreamShortcutsSectionState();
}

class _StreamShortcutsSectionState extends State<StreamShortcutsSection> {
  List<StreamShortcut> _shortcuts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final store = await StreamShortcutsStore.load();
    if (!mounted) return;
    setState(() {
      _shortcuts = store.shortcuts;
      _loading = false;
    });
  }

  Future<void> _editShortcut({StreamShortcut? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final nameOk = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New shortcut' : 'Edit shortcut'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. Close app',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Next')),
        ],
      ),
    );
    if (nameOk != true || !mounted) return;

    final name = nameController.text.trim();
    if (name.isEmpty) return;

    final chord = await showKeyboardChordEditorSheet(
      context: context,
      title: 'Keys for $name',
      initialMoonlightKeyCodes: existing?.moonlightKeyCodes ?? const [],
    );
    if (!mounted || chord == null) return;

    final store = await StreamShortcutsStore.load();
    if (existing == null) {
      await store.addNew(
        name: name,
        moonlightKeyCodes: chord.moonlightKeyCodes,
        keyLabel: chord.keyLabel,
      );
    } else {
      await store.upsert(
        existing.copyWith(
          name: name,
          moonlightKeyCodes: chord.moonlightKeyCodes,
          keyLabel: chord.keyLabel,
        ),
      );
    }
    await _reload();
  }

  Future<void> _deleteShortcut(StreamShortcut shortcut) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete shortcut?'),
        content: Text('Remove "${shortcut.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final store = await StreamShortcutsStore.load();
    await store.remove(shortcut.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Shortcuts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              onPressed: () => _editShortcut(),
              icon: const Icon(Icons.add),
              tooltip: 'Add shortcut',
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Named keyboard chords sent to your Mac during a stream. '
          'Use the Shortcuts button in the stream notification to fire them over the video.',
        ),
        const SizedBox(height: 12),
        if (_shortcuts.isEmpty)
          const Text('No shortcuts yet. Tap + to add one.')
        else
          for (final shortcut in _shortcuts)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(shortcut.name),
                subtitle: Text(shortcut.keyLabel),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () => _editShortcut(existing: shortcut),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _deleteShortcut(shortcut),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
