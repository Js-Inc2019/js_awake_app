// lib/core/theme/app_theme.dart
// J's FIELD — Asphalt Dawn ThemeData

import 'package:flutter/material.dart';
import 'field_tokens.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: FieldTokens.bgBase,

    colorScheme: const ColorScheme.dark(
      primary:     FieldTokens.accent,
      secondary:   FieldTokens.textSupport,
      surface:     FieldTokens.surfaceCard,
      error:       FieldTokens.statusError,
      // primary が accent なので onPrimary は「アクセント上の文字」でなければ読めない
      onPrimary:   FieldTokens.onAccent,
      onSecondary: FieldTokens.textBody,
      onSurface:   FieldTokens.textBody,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: FieldTokens.bgBase,
      foregroundColor: FieldTokens.textBody,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: FieldTokens.accent,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: FieldTokens.accent),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: FieldTokens.surfaceRaised,
      selectedItemColor: FieldTokens.accent,
      unselectedItemColor: FieldTokens.textFaint,
      selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
      unselectedLabelStyle: TextStyle(fontSize: 11),
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    cardTheme: CardThemeData(
      color: FieldTokens.surfaceCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: FieldTokens.outline),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: FieldTokens.accent,
        foregroundColor: FieldTokens.onAccent,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: FieldTokens.accent,
        side: const BorderSide(color: FieldTokens.outline),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: FieldTokens.accent),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FieldTokens.surfaceRaised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: FieldTokens.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: FieldTokens.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: FieldTokens.accent, width: 2),
      ),
      labelStyle: const TextStyle(color: FieldTokens.textSupport),
      hintStyle: const TextStyle(color: FieldTokens.textFaint),
    ),

    textTheme: const TextTheme(
      displayLarge:   TextStyle(color: FieldTokens.textBody),
      displayMedium:  TextStyle(color: FieldTokens.textBody),
      displaySmall:   TextStyle(color: FieldTokens.textBody),
      headlineLarge:  TextStyle(color: FieldTokens.textBody),
      headlineMedium: TextStyle(color: FieldTokens.textBody),
      headlineSmall:  TextStyle(color: FieldTokens.textBody),
      titleLarge:     TextStyle(color: FieldTokens.textBody, fontWeight: FontWeight.bold),
      titleMedium:    TextStyle(color: FieldTokens.textBody),
      titleSmall:     TextStyle(color: FieldTokens.textBody),
      bodyLarge:      TextStyle(color: FieldTokens.textBody),
      bodyMedium:     TextStyle(color: FieldTokens.textBody),
      bodySmall:      TextStyle(color: FieldTokens.textSupport),
      labelLarge:     TextStyle(color: FieldTokens.textBody),
      labelMedium:    TextStyle(color: FieldTokens.textSupport),
      labelSmall:     TextStyle(color: FieldTokens.textFaint),
    ),

    dividerTheme: const DividerThemeData(color: FieldTokens.outline, thickness: 1),
    dividerColor: FieldTokens.outline,

    iconTheme: const IconThemeData(color: FieldTokens.textSupport),
    primaryIconTheme: const IconThemeData(color: FieldTokens.textBody),

    dialogTheme: const DialogThemeData(
      backgroundColor: FieldTokens.surfaceCard,
      titleTextStyle: TextStyle(color: FieldTokens.textBody, fontSize: 18, fontWeight: FontWeight.bold),
      contentTextStyle: TextStyle(color: FieldTokens.textBody),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: FieldTokens.surfaceCard,
      modalBackgroundColor: FieldTokens.surfaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),

    snackBarTheme: const SnackBarThemeData(
      backgroundColor: FieldTokens.surfaceCard,
      contentTextStyle: TextStyle(color: FieldTokens.textBody),
      actionTextColor: FieldTokens.accent,
    ),

    popupMenuTheme: const PopupMenuThemeData(
      color: FieldTokens.surfaceCard,
      textStyle: TextStyle(color: FieldTokens.textBody),
    ),

    listTileTheme: const ListTileThemeData(
      textColor: FieldTokens.textBody,
      iconColor: FieldTokens.textSupport,
      tileColor: FieldTokens.surfaceCard,
    ),

    chipTheme: ChipThemeData(
      backgroundColor: FieldTokens.surfaceCard,
      selectedColor: FieldTokens.accent,
      secondarySelectedColor: FieldTokens.accent,
      labelStyle: const TextStyle(color: FieldTokens.textBody, fontSize: 13),
      // selectedColor が accent のため、選択時ラベルは「アクセント上の文字」
      secondaryLabelStyle: const TextStyle(color: FieldTokens.onAccent, fontSize: 13),
      side: const BorderSide(color: FieldTokens.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? FieldTokens.accent : FieldTokens.outline),
      checkColor: WidgetStateProperty.all(FieldTokens.onAccent),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? FieldTokens.accent : FieldTokens.textFaint),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? FieldTokens.accent.withValues(alpha: 0.5)
              : FieldTokens.outline),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(color: FieldTokens.accent),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: FieldTokens.accent,
      foregroundColor: FieldTokens.onAccent,
    ),

    drawerTheme: const DrawerThemeData(backgroundColor: FieldTokens.surfaceRaised),

    tabBarTheme: const TabBarThemeData(
      labelColor: FieldTokens.accent,
      unselectedLabelColor: FieldTokens.textFaint,
      indicatorColor: FieldTokens.accent,
      dividerColor: FieldTokens.outline,
    ),

    fontFamily: 'NotoSansJP',
  );
}
