import 'package:flutter/foundation.dart';

import 'user_preferences_service.dart';

enum AppLanguage { es, en }

class TranslationService extends ChangeNotifier {
  TranslationService._();

  static final TranslationService instance = TranslationService._();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService.instance;

  AppLanguage _currentLanguage = AppLanguage.es;

  AppLanguage get currentLanguage => _currentLanguage;

  bool get isSpanish => _currentLanguage == AppLanguage.es;

  String get currentLocale => isSpanish ? 'es-CL' : 'en-US';

  // =========================================================
  // INICIALIZACIÓN
  // =========================================================

  Future<void> initialize() async {
    await loadCurrentUserPreferences(notify: false, forceRefresh: false);
  }

  // =========================================================
  // CARGAR CUENTA ACTUAL
  // =========================================================

  Future<void> loadCurrentUserPreferences({
    bool forceRefresh = false,
    bool notify = true,
  }) async {
    final String? uid = _userPreferencesService.currentUid;

    // Sin sesión dejamos la interfaz pública
    // en español.
    if (uid == null) {
      final bool changed = _currentLanguage != AppLanguage.es;

      _currentLanguage = AppLanguage.es;

      if (notify && changed) {
        notifyListeners();
      }

      return;
    }

    final UserPreferences preferences = await _userPreferencesService
        .getPreferencesForUser(uid, forceRefresh: forceRefresh);

    final AppLanguage newLanguage = preferences.language == 'en'
        ? AppLanguage.en
        : AppLanguage.es;

    final bool changed = _currentLanguage != newLanguage;

    _currentLanguage = newLanguage;

    if (notify && changed) {
      notifyListeners();
    }
  }

  // =========================================================
  // CAMBIAR IDIOMA
  // =========================================================

  Future<void> changeLanguage(AppLanguage language) async {
    if (_currentLanguage == language) {
      return;
    }

    // Cambio inmediato en pantalla.
    _currentLanguage = language;

    notifyListeners();

    // Persistencia exclusiva para el UID activo.
    await _userPreferencesService.setLanguage(language.name);
  }

  Future<void> toggleLanguage() async {
    await changeLanguage(isSpanish ? AppLanguage.en : AppLanguage.es);
  }

  // =========================================================
  // CERRAR SESIÓN
  // =========================================================

  void resetForSignedOutUser() {
    if (_currentLanguage == AppLanguage.es) {
      return;
    }

    _currentLanguage = AppLanguage.es;

    notifyListeners();
  }
}
