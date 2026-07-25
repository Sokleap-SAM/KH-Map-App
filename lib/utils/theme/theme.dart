import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kh_map_app/utils/theme/custom_theme/text_theme.dart';
import '../constants/colors.dart';
import 'app_palette.dart';

class AppTheme {
  AppTheme._();

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: GoogleFonts.inter().fontFamily,
    textTheme: AppTextTheme.lightTextTheme,
    primaryColor: AppColors.primaryColor,
    scaffoldBackgroundColor: Colors.white,
    colorScheme: ColorScheme.light(
      primary: AppColors.primaryColor,
      secondary: AppColors.secondaryColor,
    ),
    extensions: const [AppPalette.light],
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: GoogleFonts.inter().fontFamily,
    textTheme: AppTextTheme.darkTextTheme,
    primaryColor: AppColors.primaryColor,
    scaffoldBackgroundColor: AppColors.primaryColor,
    colorScheme: ColorScheme.dark(
      primary: AppColors.secondaryColor,
      secondary: AppColors.secondaryColor,
      surface: AppColors.primaryColor,
    ),
    extensions: const [AppPalette.dark],
  );
}
