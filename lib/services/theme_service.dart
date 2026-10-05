import 'package:flutter/material.dart';

import 'user_preferences_service.dart';

class ThemeService extends ChangeNotifier {
  ThemeService._() : _persistTheme = _persistProductionTheme;

  @visibleForTesting
  ThemeService.forTesting(Future<void> Function(String theme) persistTheme)
    : _persistTheme = persistTheme;

  static final ThemeService instance = ThemeService._();

  UserPreferencesService get _userPreferencesService =>
      UserPreferencesService.instance;
  final Future<void> Function(String theme) _persistTheme;

  static Future<void> _persistProductionTheme(String theme) {
    return UserPreferencesService.instance.setTheme(theme);
  }

  ThemeMode _themeMode = ThemeMode.light;
  bool _savingTheme = false;
  int _stateVersion = 0;

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

    applyUserPreference(preferences.theme, notify: notify);
  }

  void applyUserPreference(String theme, {bool notify = true}) {
    final ThemeMode newTheme = theme == 'dark'
        ? ThemeMode.dark
        : ThemeMode.light;
    final bool changed = _themeMode != newTheme;
    _stateVersion += 1;
    _savingTheme = false;
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
    final ThemeMode previousTheme = _themeMode;

    if (_themeMode == newTheme || _savingTheme) {
      return;
    }

    // Primero actualizamos la interfaz
    // inmediatamente.
    _savingTheme = true;
    final int operationVersion = ++_stateVersion;
    _themeMode = newTheme;

    notifyListeners();

    // Después persistimos la preferencia
    // exclusivamente para el UID actual.
    try {
      await _persistTheme(enabled ? 'dark' : 'light');
    } catch (_) {
      if (_stateVersion == operationVersion) {
        _themeMode = previousTheme;
        notifyListeners();
      }
      rethrow;
    } finally {
      if (_stateVersion == operationVersion) {
        _savingTheme = false;
      }
    }
  }

  Future<void> toggleTheme() async {
    await setDarkMode(!isDarkMode);
  }

  // =========================================================
  // CERRAR SESIÓN
  // =========================================================

  void resetForSignedOutUser() {
    _stateVersion += 1;
    _savingTheme = false;
    if (_themeMode == ThemeMode.light) {
      return;
    }

    _themeMode = ThemeMode.light;

    notifyListeners();
  }
}
