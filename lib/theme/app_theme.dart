import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta "urban" tomada directamente del mockup de diseño de Nexo.
class AppColors {
  static const urban950 = Color(0xFF0B0C0D);
  static const urban900 = Color(0xFF0F1012);
  static const urban800 = Color(0xFF17191D);
  static const urban700 = Color(0xFF21242A);
  static const urban600 = Color(0xFF2E323B);
  static const urban500 = Color(0xFF474D5A);
  static const urban300 = Color(0xFF9EA5B3);
  static const urban100 = Color(0xFFF0F2F5);

  static const income = Color(0xFF10B981);
  static const expense = Color(0xFFF43F5E);
  static const urbanBlue = Color(0xFF3B82F6);
}

class AppTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    final displayFont = GoogleFonts.spaceGrotesk();
    final bodyFont = GoogleFonts.plusJakartaSans();

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.urban950,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.urbanBlue,
        secondary: AppColors.urbanBlue,
        surface: AppColors.urban900,
        error: AppColors.expense,
      ),
      textTheme: GoogleFonts.plusJakartaSansTextTheme(base.textTheme).apply(
        bodyColor: AppColors.urban100,
        displayColor: AppColors.urban100,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.urban900,
        elevation: 0,
        titleTextStyle: displayFont.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.urban950,
        selectedItemColor: AppColors.urbanBlue,
        unselectedItemColor: AppColors.urban300,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.urban800,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.urban700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.urban700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.urbanBlue),
        ),
        hintStyle: bodyFont.copyWith(color: AppColors.urban500, fontSize: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.income,
        contentTextStyle: bodyFont.copyWith(
          color: AppColors.urban950,
          fontWeight: FontWeight.bold,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static TextStyle display({
    double size = 16,
    FontWeight weight = FontWeight.bold,
    Color color = Colors.white,
  }) =>
      GoogleFonts.spaceGrotesk(fontSize: size, fontWeight: weight, color: color);
}
