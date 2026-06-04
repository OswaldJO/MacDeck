import 'dart:io';

import 'package:flutter/material.dart';

import '../data/gamepad_elements.dart';
import '../data/gamepad_swap_toggle.dart';
import '../data/moonlight_key_codes.dart';
import '../services/stream_controller_mapping_store.dart';
import '../services/stream_controller_settings.dart';
import '../services/streaming_bridge.dart';
import 'companion_insets.dart';

/// Full button-mapping list for the Controller tab (Android native stream).
class ControllerMappingSection extends StatefulWidget {
  const ControllerMappingSection({
    super.key,
    required this.bridge,
    required this.bindings,
    required this.connectedControllers,
    required this.onBindingsChanged,
  });

  final StreamingBridge bridge;
  final List<StreamControllerElementMapping> bindings;
  final List<ConnectedControllerInfo> connectedControllers;
  final ValueChanged<List<StreamControllerElementMapping>> onBindingsChanged;

  @override
  State<ControllerMappingSection> createState() => _ControllerMappingSectionState();
}

class _ControllerMappingSectionState extends State<ControllerMappingSection> {
  String? _listeningElementId;

  StreamControllerElementMapping? _mappingFor(String elementId) {
    for (final b in widget.bindings) {
      if (b.sourceElementId == elementId) return b;
    }
    return null;
  }

  Future<void> _persist(StreamControllerElementMapping mapping) async {
    final store = await StreamControllerMappingStore.load();
    await store.upsert(mapping);
    final updated = [
      ...widget.bindings.where((b) => b.sourceElementId != mapping.sourceElementId),
      mapping,
    ];
    widget.onBindingsChanged(updated);
  }

  Future<void> _assignSwapToggle(GamepadElement element) async {
    if (!canMapSwapToggleTo(element.id)) return;
    final existing = _mappingFor(element.id);
    await _persist(
      StreamControllerElementMapping(
        sourceElementId: element.id,
        sourceLabel: element.label,
        moonlightKeyCodes: const [],
        targetLabel: kSwapToggleTargetLabel,
        targetAction: kSwapToggleTargetAction,
        physicalKeyCode: existing?.physicalKeyCode,
        manualPhysicalLink: existing?.manualPhysicalLink ?? false,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${element.label} → $kSwapToggleTargetLabel')),
    );
  }

  Future<void> _clearMapping(String elementId) async {
    final store = await StreamControllerMappingStore.load();
    await store.removeForElement(elementId);
    widget.onBindingsChanged(
      widget.bindings.where((b) => b.sourceElementId != elementId).toList(),
    );
  }

  Future<void> _editKeyboardChord(GamepadElement element) async {
    final existing = _mappingFor(element.id);
    final selected = List<MoonlightKeyOption>.from(
      existing?.moonlightKeyCodes
              .map((c) => moonlightKeyByCode(c))
              .whereType<MoonlightKeyOption>() ??
          const [],
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
                  Text(
                    'Keys for ${element.label}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add keys in order (e.g. Shift, then F). All keys are pressed together when you use this button.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final key in selected)
                        InputChip(
                          label: Text(key.label),
                          onDeleted: () {
                            setSheetState(() => selected.remove(key));
                          },
                        ),
                      if (selected.isEmpty)
                        const Text('No keys assigned'),
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
                        onPressed: () => Navigator.pop(sheetContext, true),
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

    if (saved != true || !mounted) return;

    if (selected.isEmpty) {
      await _clearMapping(element.id);
      return;
    }

    final codes = selected.map((k) => k.moonlightKeyCode).toList();
    await _persist(
      StreamControllerElementMapping(
        sourceElementId: element.id,
        sourceLabel: element.label,
        moonlightKeyCodes: codes,
        targetLabel: selected.map((k) => k.label).join(' + '),
        physicalKeyCode: existing?.physicalKeyCode,
        manualPhysicalLink: existing?.manualPhysicalLink ?? false,
        targetAction: null,
      ),
    );
  }

  Future<void> _linkGamepadButton(GamepadElement element) async {
    setState(() => _listeningElementId = element.id);
    final press = await widget.bridge.awaitGamepadButtonPress();
    if (!mounted) return;
    setState(() => _listeningElementId = null);
    if (press == null || press.keyCode == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No gamepad button detected — try Refresh gamepads first.')),
        );
      }
      return;
    }

    final existing = _mappingFor(element.id);
    await _persist(
      StreamControllerElementMapping(
        sourceElementId: element.id,
        sourceLabel: element.label,
        moonlightKeyCodes: existing?.moonlightKeyCodes ?? const [],
        targetLabel: existing?.targetLabel ?? 'Unmapped',
        physicalKeyCode: press.keyCode,
        manualPhysicalLink: true,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Linked ${element.label} → ${press.label} (manual)')),
    );
  }

  String _physicalSubtitle(StreamControllerElementMapping? mapping) {
    if (mapping == null) return 'Gamepad: auto-detect';
    if (mapping.manualPhysicalLink && mapping.physicalKeyCode != null) {
      return 'Gamepad: manual key ${mapping.physicalKeyCode}';
    }
    return 'Gamepad: auto-detect';
  }

  int _gridColumnCount(double width, double height) {
    if (width <= height) return 1;
    if (width >= 900) return 3;
    if (width >= 520) return 2;
    return 1;
  }

  Widget _mappingCard(GamepadElement element) {
    final mapping = _mappingFor(element.id);
    final listening = _listeningElementId == element.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              element.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              mapping?.isSwapToggleMapping == true
                  ? 'Action: ${mapping!.targetLabel}'
                  : mapping?.hasKeyboardMapping == true
                      ? 'Mac keys: ${mapping!.targetLabel}'
                      : 'Mac keys: none',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              _physicalSubtitle(mapping),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: listening ? null : () => _editKeyboardChord(element),
                  child: const Text('Assign keys'),
                ),
                OutlinedButton(
                  onPressed: listening ? null : () => _linkGamepadButton(element),
                  child: Text(listening ? 'Press a button…' : 'Link gamepad'),
                ),
                if (canMapSwapToggleTo(element.id))
                  OutlinedButton(
                    onPressed: listening ? null : () => _assignSwapToggle(element),
                    child: const Text('Assign Swap'),
                  ),
                if (mapping != null)
                  TextButton(
                    onPressed: () => _clearMapping(element.id),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mappingGrid(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _gridColumnCount(constraints.maxWidth, constraints.maxHeight);
        if (columns == 1) {
          return Column(
            children: [
              for (final element in kMappableGamepadElements) ...[
                _mappingCard(element),
                const SizedBox(height: 8),
              ],
            ],
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            mainAxisExtent: 152,
          ),
          itemCount: kMappableGamepadElements.length,
          itemBuilder: (context, index) => _mappingCard(kMappableGamepadElements[index]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return Text(
        'Button→keyboard mapping during streams is available on Android.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mapped buttons send keyboard chords or toggle Swap mouse mode (except A, B, and X — '
          'those are used by Swap for click and drag). Unmapped buttons are ignored by the phone UI.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (widget.connectedControllers.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final controller in widget.connectedControllers)
            if (controller.detectedButtons.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${controller.name} detected: '
                  '${controller.detectedButtons.map((b) => b.label).join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
        ],
        const SizedBox(height: 12),
        _mappingGrid(context),
      ],
    );
  }
}
