// lib/core/theme/app_theme.dart
// J's FIELD — Asphalt Dawn ThemeData

import 'package:flutter/material.dart';
import 'js_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: JsColors.background,

    colorScheme: const ColorScheme.dark(
      primary:     JsColors.accent,
      secondary:   JsColors.textMid,
      surface:     JsColors.surface,
      error:       JsColors.error,
      // primary が accent なので onPrimary は「アクセント上の文字」でなければ読めない
      onPrimary:   JsPalette.onAccent,
      onSecondary: JsColors.textStrong,
      onSurface:   JsColors.textStrong,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: JsColors.background,
      foregroundColor: JsColors.textStrong,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: JsColors.accent,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: JsColors.accent),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: JsColors.surfaceAlt,
      selectedItemColor: JsColors.accent,
      unselectedItemColor: JsColors.textWeak,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      unselectedLabelStyle: TextStyle(fontSize: 11),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: JsColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: JsColors.border),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: JsColors.accent,
        foregroundColor: JsPalette.onAccent,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: JsColors.accent,
        side: const BorderSide(color: JsColors.border),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: JsColors.accent),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JsColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JsColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JsColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JsColors.accent, width: 2),
      ),
      labelStyle: const TextStyle(color: JsColors.textMid),
      hintStyle: const TextStyle(color: JsColors.textWeak),
    ),

    textTheme: const TextTheme(
      displayLarge:   TextStyle(color: JsColors.textStrong),
      displayMedium:  TextStyle(color: JsColors.textStrong),
      displaySmall:   TextStyle(color: JsColors.textStrong),
      headlineLarge:  TextStyle(color: JsColors.textStrong),
      headlineMedium: TextStyle(color: JsColors.textStrong),
      headlineSmall:  TextStyle(color: JsColors.textStrong),
      titleLarge:     TextStyle(color: JsColors.textStrong, fontWeight: FontWeight.bold),
      titleMedium:    TextStyle(color: JsColors.textStrong),
      titleSmall:     TextStyle(color: JsColors.textStrong),
      bodyLarge:      TextStyle(color: JsColors.textStrong),
      bodyMedium:     TextStyle(color: JsColors.textStrong),
      bodySmall:      TextStyle(color: JsColors.textMid),
      labelLarge:     TextStyle(color: JsColors.textStrong),
      labelMedium:    TextStyle(color: JsColors.textMid),
      labelSmall:     TextStyle(color: JsColors.textWeak),
    ),

    dividerTheme: const DividerThemeData(color: JsColors.divider, thickness: 1),
    dividerColor: JsColors.divider,

    iconTheme: const IconThemeData(color: JsColors.textMid),
    primaryIconTheme: const IconThemeData(color: JsColors.textStrong),

    dialogTheme: const DialogThemeData(
      backgroundColor: JsColors.surface,
      titleTextStyle: TextStyle(color: JsColors.textStrong, fontSize: 18, fontWeight: FontWeight.bold),
      contentTextStyle: TextStyle(color: JsColors.textStrong),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: JsColors.surface,
      modalBackgroundColor: JsColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),

    snackBarTheme: const SnackBarThemeData(
      backgroundColor: JsColors.surface,
      contentTextStyle: TextStyle(color: JsColors.textStrong),
      actionTextColor: JsColors.accent,
    ),

    popupMenuTheme: const PopupMenuThemeData(
      color: JsColors.surface,
      textStyle: TextStyle(color: JsColors.textStrong),
    ),

    listTileTheme: const ListTileThemeData(
      textColor: JsColors.textStrong,
      iconColor: JsColors.textMid,
      tileColor: JsColors.surface,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: JsColors.surface,
      selectedColor: JsColors.accent,
      secondarySelectedColor: JsColors.accent,
      labelStyle: const TextStyle(color: JsColors.textStrong, fontSize: 13),
      // selectedColor が accent のため、選択時ラベルは「アクセント上の文字」
      secondaryLabelStyle: const TextStyle(color: JsPalette.onAccent, fontSize: 13),
      side: const BorderSide(color: JsColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? JsColors.accent : JsColors.border),
      checkColor: WidgetStateProperty.all(JsPalette.onAccent),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? JsColors.accent : JsColors.textWeak),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? JsColors.accent.withValues(alpha: 0.5)
              : JsColors.border),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: JsColors.accent),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: JsColors.accent,
      foregroundColor: JsPalette.onAccent,
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: JsColors.surfaceAlt),

    tabBarTheme: const TabBarThemeData(
      labelColor: JsColors.accent,
      unselectedLabelColor: JsColors.textWeak,
      indicatorColor: JsColors.accent,
      dividerColor: JsColors.border,
    ),

    fontFamily: 'NotoSansJP',
  );
}
