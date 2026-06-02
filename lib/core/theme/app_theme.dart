import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.gunmetal,
    primaryColor: AppColors.darkNavy,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.gold,
      secondary: AppColors.steelSilver,
      surface: AppColors.gunmetalLight,
      onPrimary: AppColors.textDark,
      onSecondary: AppColors.textPrimary,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.darkNavy,
      foregroundColor: AppColors.offWhite,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.offWhite,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
      iconTheme: IconThemeData(color: AppColors.gold),
    ),
    cardTheme: CardThemeData(
      color: AppColors.gunmetalLight,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.textDark,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.gold,
        side: const BorderSide(color: AppColors.gold),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.gunmetalLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF4A4A4A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF4A4A4A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.gold, width: 2),
      ),
      labelStyle: const TextStyle(color: AppColors.steelSilver),
      hintStyle: const TextStyle(color: Color(0xFF666666)),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkNavy,
      selectedItemColor: AppColors.gold,
      unselectedItemColor: AppColors.steelSilver,
    ),
    dividerColor: const Color(0x4D8A9BA8),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF4A4A4A),
      thickness: 1,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: AppColors.offWhite,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
      headlineMedium: TextStyle(
        color: AppColors.offWhite,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(
        color: AppColors.offWhite,
        height: 1.8,
      ),
      bodyMedium: TextStyle(
        color: AppColors.steelSilver,
        height: 1.6,
      ),
    ),
  );
}
