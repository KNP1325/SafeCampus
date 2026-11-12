import 'package:flutter/material.dart';

abstract final class SafeCampusColors {
  static const forest = Color(0xFF123B2F);
  static const green = Color(0xFF087A50);
  static const gold = Color(0xFFC6A64B);
  static const paper = Color(0xFFF7F7EF);
  static const paleGreen = Color(0xFFDCE8D8);
}

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: SafeCampusColors.forest,
      primary: SafeCampusColors.forest,
      secondary: SafeCampusColors.gold,
      surface: SafeCampusColors.paper,
    ),
    scaffoldBackgroundColor: SafeCampusColors.paper,
    useMaterial3: true,
  );
}
