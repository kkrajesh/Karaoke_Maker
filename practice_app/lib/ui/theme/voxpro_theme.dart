import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VoxProTheme {
  // Deep, technical dark mode palette
  static const Color background = Color(0xFF0F1115);
  static const Color sidebar = Color(0xFF16191E);
  static const Color cardBg = Color(0xFF1E222A);
  static const Color accent = Color(0xFF00FFCC); // Neon teal for instrumental/active states
  static const Color vocalAccent = Color(0xFFFF00FF); // Neon purple/pink for vocals guide
  static const Color instAccent = Color(0xFF00BFFF); // Deep Sky Blue for instrumental
  static const Color pitchAccent = Color(0xFFFFD700); // Gold for pitch profile
  static const Color mapAccent = Color(0xFFFF4500); // Orange Red for vocal map
  static const Color lyricsAccent = Color(0xFF32CD32); // Lime Green for lyrics
  static const Color textPrimary = Color(0xFFE2E8F0);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color border = Color(0xFF2D333F);

  static ThemeData get themeData {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: cardBg,
        onSurface: textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).copyWith(
        bodyLarge: GoogleFonts.inter(color: textPrimary, fontSize: 16),
        bodyMedium: GoogleFonts.inter(color: textSecondary, fontSize: 14),
        titleLarge: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.bold),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
    );
  }
}
