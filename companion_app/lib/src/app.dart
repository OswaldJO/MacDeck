import 'package:flutter/material.dart';

import 'screens/home_page.dart';
import 'theme/companion_theme.dart';

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Playnite Companion',
      debugShowCheckedModeBanner: false,
      theme: CompanionTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
