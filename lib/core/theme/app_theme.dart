// lib/core/theme/app_theme.dart
// 株式会社J's 統一ThemeData定義
// main.dart の _buildTheme() をこちらに移行する際に使用

import 'package:flutter/material.dart';
import 'js_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: JsColors.background,
    colorScheme: const ColorScheme.dark(
      primary:     JsColors.gold,
      secondary:   JsColors.silver,
      surface:     JsColors.background,
      error:       JsColors.error,
      onPrimary:   Colors.black,
      onSecondary: JsColors.textPrimary,
      onSurface:   JsColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: JsColors.background,
      foregroundColor: JsColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: JsColors.gold,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      iconTheme: IconThemeData(color: JsColors.gold),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: JsColors.surfaceAlt,
      selectedItemColor: JsColors.gold,
      unselectedItemColor: JsColors.silver,
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
        side: const BorderSide(color: JsColors.divider),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: JsColors.gold,
        foregroundColor: Colors.black,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: JsColors.gold,
        side: const BorderSide(color: JsColors.gold),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: JsColors.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JsColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JsColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: JsColors.gold, width: 2),
      ),
      labelStyle: const TextStyle(color: JsColors.silver),
      hintStyle: const TextStyle(color: Color(0xFF666666)),
    ),
    dividerTheme: const DividerThemeData(color: JsColors.divider, thickness: 1),
    fontFamily: 'NotoSansJP',
  );
}
