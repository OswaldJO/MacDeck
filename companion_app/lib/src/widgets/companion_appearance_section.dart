import 'package:flutter/material.dart';

import '../services/companion_appearance_settings.dart';

/// Settings control for companion primary text color.
class CompanionAppearanceSection extends StatefulWidget {
  const CompanionAppearanceSection({super.key});

  @override
  State<CompanionAppearanceSection> createState() => _CompanionAppearanceSectionState();
}

class _CompanionAppearanceSectionState extends State<CompanionAppearanceSection> {
  Color _selected = CompanionAppearanceSettings.defaultPrimaryText;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await CompanionAppearanceSettings.load();
    if (!mounted) return;
    setState(() => _selected = settings.primaryTextColor);
  }

  Future<void> _applyColor(Color color) async {
    final settings = await CompanionAppearanceSettings.load();
    await settings.setPrimaryTextColor(color);
    if (!mounted) return;
    setState(() => _selected = color);
  }

  Future<void> _openCustomPicker() async {
    var draft = _selected;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Custom text color'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: draft,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Text(
                        'Preview text',
                        style: TextStyle(
                          color: draft.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _channelSlider(
                      label: 'Red',
                      value: _channelByte(draft.r).toDouble(),
                      onChanged: (v) => setDialogState(() {
                        draft = Color.fromARGB(
                          255,
                          v.round(),
                          _channelByte(draft.g),
                          _channelByte(draft.b),
                        );
                      }),
                    ),
                    _channelSlider(
                      label: 'Green',
                      value: _channelByte(draft.g).toDouble(),
                      onChanged: (v) => setDialogState(() {
                        draft = Color.fromARGB(
                          255,
                          _channelByte(draft.r),
                          v.round(),
                          _channelByte(draft.b),
                        );
                      }),
                    ),
                    _channelSlider(
                      label: 'Blue',
                      value: _channelByte(draft.b).toDouble(),
                      onChanged: (v) => setDialogState(() {
                        draft = Color.fromARGB(
                          255,
                          _channelByte(draft.r),
                          _channelByte(draft.g),
                          v.round(),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apply')),
              ],
            );
          },
        );
      },
    );
    if (saved == true) await _applyColor(draft);
  }

  static int _channelByte(double channel) => (channel * 255).round().clamp(0, 255);

  Widget _channelSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label ${value.round()}'),
        Slider(
          value: value.clamp(0, 255),
          min: 0,
          max: 255,
          divisions: 255,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Appearance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Primary text color used across tabs, lists, and dialogs. Pick a preset or tune a custom color.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in CompanionAppearanceSettings.presetTextColors)
              _ColorChip(
                label: preset.label,
                color: preset.color,
                selected: _selected.toARGB32() == preset.color.toARGB32(),
                onTap: () => _applyColor(preset.color),
              ),
            ActionChip(
              label: const Text('Custom…'),
              onPressed: _openCustomPicker,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Sample heading',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Sample body text — this is how labels and descriptions will look.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24),
              ),
            ),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
