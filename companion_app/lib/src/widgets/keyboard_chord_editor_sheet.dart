import 'package:flutter/material.dart';

import '../data/moonlight_key_codes.dart';
import 'companion_insets.dart';

/// Bottom sheet to pick an ordered keyboard chord (modifiers + keys).
Future<KeyboardChordEditResult?> showKeyboardChordEditorSheet({
  required BuildContext context,
  required String title,
  List<int> initialMoonlightKeyCodes = const [],
}) async {
  final selected = List<MoonlightKeyOption>.from(
    initialMoonlightKeyCodes
        .map((c) => moonlightKeyByCode(c))
        .whereType<MoonlightKeyOption>(),
  );

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 8,
              bottom: CompanionInsets.sheetBottom(context),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'Add keys in order (e.g. Command, Option, Escape). All keys are pressed together.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in selected)
                      InputChip(
                        label: Text(key.label),
                        onDeleted: () => setSheetState(() => selected.remove(key)),
                      ),
                    if (selected.isEmpty) const Text('No keys assigned'),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<MoonlightKeyOption>(
                  decoration: const InputDecoration(labelText: 'Add key'),
                  items: kMoonlightKeyboardKeys
                      .map(
                        (key) => DropdownMenuItem(
                          value: key,
                          child: Text(key.label),
                        ),
                      )
                      .toList(),
                  onChanged: (key) {
                    if (key == null || selected.contains(key)) return;
                    setSheetState(() => selected.add(key));
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.pop(sheetContext, true),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  if (saved != true || selected.isEmpty) return null;
  return KeyboardChordEditResult(
    moonlightKeyCodes: selected.map((k) => k.moonlightKeyCode).toList(),
    keyLabel: selected.map((k) => k.label).join(' + '),
  );
}

class KeyboardChordEditResult {
  const KeyboardChordEditResult({
    required this.moonlightKeyCodes,
    required this.keyLabel,
  });

  final List<int> moonlightKeyCodes;
  final String keyLabel;
}
