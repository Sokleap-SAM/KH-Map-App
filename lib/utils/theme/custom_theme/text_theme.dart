import 'package:flutter/material.dart';

class AppTextTheme {
  AppTextTheme._();

  static TextTheme lightTextTheme = TextTheme(
    titleLarge: const TextStyle().copyWith(
      fontSize: 24.0,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    ),
    headlineLarge: const TextStyle().copyWith(
      fontSize: 16.0,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    ),
    headlineMedium: const TextStyle().copyWith(
      fontSize: 15.0,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    ),
    bodyLarge: const TextStyle().copyWith(
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    ),
    bodyMedium: const TextStyle().copyWith(
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    ),
    bodySmall: const TextStyle().copyWith(
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    ),
    labelSmall: const TextStyle().copyWith(
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      color: Colors.black,
    ),
  );

  static TextTheme darkTextTheme = TextTheme(
    titleLarge: const TextStyle().copyWith(
      fontSize: 24.0,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    headlineLarge: const TextStyle().copyWith(
      fontSize: 16.0,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    headlineMedium: const TextStyle().copyWith(
      fontSize: 15.0,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    bodyLarge: const TextStyle().copyWith(
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    bodyMedium: const TextStyle().copyWith(
      fontSize: 12.0,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
    bodySmall: const TextStyle().copyWith(
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      color: Colors.white70,
    ),
    labelSmall: const TextStyle().copyWith(
      fontSize: 11.0,
      fontWeight: FontWeight.w500,
      color: Colors.white70,
    ),
  );
}
