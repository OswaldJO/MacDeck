import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/home_page.dart';
import 'services/companion_appearance_settings.dart';
import 'theme/companion_theme.dart';

class CompanionApp extends StatefulWidget {
  const CompanionApp({super.key});

  @override
  State<CompanionApp> createState() => _CompanionAppState();
}

class _CompanionAppState extends State<CompanionApp> {
  Color _primaryText = CompanionAppearanceSettings.defaultPrimaryText;

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppearance());
    CompanionAppearanceSettings.themeRevision.addListener(_onAppearanceChanged);
  }

  @override
  void dispose() {
    CompanionAppearanceSettings.themeRevision.removeListener(_onAppearanceChanged);
    super.dispose();
  }

  void _onAppearanceChanged() {
    unawaited(_loadAppearance());
  }

  Future<void> _loadAppearance() async {
    final settings = await CompanionAppearanceSettings.load();
    if (!mounted) return;
    setState(() => _primaryText = settings.primaryTextColor);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Playnite Companion',
      debugShowCheckedModeBanner: false,
      theme: CompanionTheme.dark(primaryText: _primaryText),
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
