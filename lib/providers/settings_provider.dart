import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants/text_strings.dart';

class SettingsProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('km'); // Default to Khmer

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;

  /// Raw language code of the active locale ('km' or 'en').
  String get languageCode => _locale.languageCode;

  /// Active language as a typed enum.
  AppLanguage get appLanguage =>
      _locale.languageCode == 'en' ? AppLanguage.en : AppLanguage.km;

  /// The localized static-text store for the active language. Read strings in
  /// widgets via `context.watch<SettingsProvider>().t`.
  AppTexts get t => AppTexts(appLanguage);

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('theme_mode') ?? 0;
    final langCode = prefs.getString('language_code') ?? 'km';

    _themeMode = ThemeMode.values[themeIndex];
    _locale = Locale(langCode);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
  }

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme(bool isOn) {
    setThemeMode(isOn ? ThemeMode.dark : ThemeMode.light);
  }
}