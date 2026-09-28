import 'package:flutter/material.dart';

/// Chrome theme for the window. Terminal text stays monospace inside xterm;
/// the rest of the UI uses the platform sans so it does not look like a log.
ThemeData jtermTheme({required bool dark, required Color seed}) {
  final scheme = _scheme(dark: dark, seed: seed);
  final radius = BorderRadius.circular(10);

  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: scheme.brightness,
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      bodyMedium: TextStyle(fontSize: 13, height: 1.35),
      bodySmall: TextStyle(fontSize: 12, height: 1.3),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainerLow,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerHigh,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        foregroundColor: scheme.onSurfaceVariant,
        hoverColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: TextStyle(fontSize: 13, color: scheme.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark
          ? const Color(0xFF0E141B)
          : scheme.surface,
      hintStyle: TextStyle(color: scheme.outline, fontSize: 13),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border(scheme.outlineVariant),
      enabledBorder: border(scheme.outlineVariant),
      focusedBorder: border(scheme.primary, 1.4),
      errorBorder: border(scheme.error),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
    ),
  );
}

ColorScheme _scheme({required bool dark, required Color seed}) {
  final seeded = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: dark ? Brightness.dark : Brightness.light,
  );
  if (!dark) {
    return seeded.copyWith(
      surface: const Color(0xFFF3F6F4),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFE7EEEA),
      surfaceContainer: const Color(0xFFDCE6E1),
      surfaceContainerHigh: const Color(0xFFFFFFFF),
      surfaceContainerHighest: const Color(0xFFD3DED8),
    );
  }
  return seeded.copyWith(
    surface: const Color(0xFF0C1116),
    surfaceDim: const Color(0xFF0C1116),
    surfaceBright: const Color(0xFF1A232C),
    surfaceContainerLowest: const Color(0xFF090D11),
    surfaceContainerLow: const Color(0xFF121920),
    surfaceContainer: const Color(0xFF172029),
    surfaceContainerHigh: const Color(0xFF1C2732),
    surfaceContainerHighest: const Color(0xFF243140),
    onSurface: const Color(0xFFE7EEF2),
    onSurfaceVariant: const Color(0xFF9AABBA),
    outline: const Color(0xFF3D4E5C),
    outlineVariant: const Color(0xFF24303A),
  );
}
