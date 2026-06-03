import 'package:flutter/material.dart';

/// Dark-first Material 3 theme for Playnite Companion.
abstract final class CompanionTheme {
  static const Color _background = Color(0xFF0E1014);
  static const Color _surface = Color(0xFF161920);
  static const Color _surfaceHigh = Color(0xFF1E232D);
  static const Color _card = Color(0xFF1C2028);
  static const Color _seed = Color(0xFF6EB5FF);

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      surface: _surface,
      surfaceContainerHighest: _surfaceHigh,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: _background,
      appBarTheme: AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      cardTheme: CardThemeData(
        color: _card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface,
        indicatorColor: _seed.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(color: scheme.primary, fontSize: 12);
          }
          return TextStyle(color: scheme.onSurfaceVariant, fontSize: 12);
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _surfaceHigh,
        modalBackgroundColor: _surfaceHigh,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.35)),
    );
  }
}
