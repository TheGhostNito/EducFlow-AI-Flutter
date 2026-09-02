import 'package:flutter/material.dart';

import 'user_preferences_service.dart';

class ThemeService extends ChangeNotifier {
  ThemeService._();

  static final ThemeService instance = ThemeService._();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService.instance;

  ThemeMode _themeMode = ThemeMode.light;

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // =========================================================
  // INICIALIZACIÓN
  // =========================================================

  Future<void> initialize() async {
    await loadCurrentUserPreferences(notify: false);
  }

  // =========================================================
  // CARGAR CUENTA ACTUAL
  // =========================================================

  Future<void> loadCurrentUserPreferences({
    bool forceRefresh = true,
    bool notify = true,
  }) async {
    final String? uid = _userPreferencesService.currentUid;

    // Si no hay sesión iniciada,
    // la pantalla pública utiliza el tema
    // predeterminado.
    if (uid == null) {
      final bool changed = _themeMode != ThemeMode.light;

      _themeMode = ThemeMode.light;

      if (notify && changed) {
        notifyListeners();
      }

      return;
    }

    final UserPreferences preferences = await _userPreferencesService
        .getPreferencesForUser(uid, forceRefresh: forceRefresh);

    final ThemeMode newTheme = preferences.theme == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;

    final bool changed = _themeMode != newTheme;

    _themeMode = newTheme;

    if (notify && changed) {
      notifyListeners();
    }
  }

  // =========================================================
  // CAMBIAR TEMA
  // =========================================================

  Future<void> setDarkMode(bool enabled) async {
    final ThemeMode newTheme = enabled ? ThemeMode.dark : ThemeMode.light;

    if (_themeMode == newTheme) {
      return;
    }

    // Primero actualizamos la interfaz
    // inmediatamente.
    _themeMode = newTheme;

    notifyListeners();

    // Después persistimos la preferencia
    // exclusivamente para el UID actual.
    await _userPreferencesService.setTheme(enabled ? 'dark' : 'light');
  }

  Future<void> toggleTheme() async {
    await setDarkMode(!isDarkMode);
  }

  // =========================================================
  // CERRAR SESIÓN
  // =========================================================

  void resetForSignedOutUser() {
    if (_themeMode == ThemeMode.light) {
      return;
    }

    _themeMode = ThemeMode.light;

    notifyListeners();
  }
}
