import 'package:flutter/material.dart';

/// 取当前主题的次级面板色（surface2），根据亮/暗自动切换。
Color surface2Of(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppTheme.darkSurface2
        : AppTheme.lightSurface2;

/// 亮暗主题配色（对应网页预览版）。
class AppTheme {
  AppTheme._();

  static const Color green = Color(0xFF00E07D);
  static const Color green2 = Color(0xFF2EE59B);
  static const Color red = Color(0xFFFF453A);
  static const Color orange = Color(0xFFFF9F0A);
  static const Color cyan = Color(0xFF00D0FF);
  static const Color blue = Color(0xFF0A84FF);

  static const Color darkBg = Color(0xFF0A0A0A);
  static const Color darkSurface = Color(0xFF141414);
  static const Color darkSurface2 = Color(0xFF1C1C1C);
  static const Color darkText = Color(0xFFE8E8E8);
  static const Color darkDim = Color(0xFF8A8A8A);

  static const Color lightBg = Color(0xFFF2F4F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurface2 = Color(0xFFE5E8ED);
  static const Color lightText = Color(0xFF1C1F24);
  static const Color lightDim = Color(0xFF7A818C);

  static ThemeData dark() => _build(
        bg: darkBg,
        surface: darkSurface,
        surface2: darkSurface2,
        text: darkText,
        dim: darkDim,
        isDark: true,
      );

  static ThemeData light() => _build(
        bg: lightBg,
        surface: lightSurface,
        surface2: lightSurface2,
        text: lightText,
        dim: lightDim,
        isDark: false,
      );

  static ThemeData _build({
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color text,
    required Color dim,
    required bool isDark,
  }) {
    final scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: green,
      onPrimary: const Color(0xFF03130A),
      secondary: cyan,
      onSecondary: text,
      error: red,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      background: bg,
      onBackground: text,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: null,
      textTheme: TextTheme(
        bodyMedium: TextStyle(color: text, fontSize: 14),
        bodySmall: TextStyle(color: dim, fontSize: 12),
        titleMedium: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: true,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: green,
        unselectedItemColor: dim,
        type: BottomNavigationBarType.fixed,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        hintStyle: TextStyle(color: dim, fontSize: 14),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: TextStyle(color: text, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
