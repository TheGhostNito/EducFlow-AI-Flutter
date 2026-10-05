import 'package:flutter/foundation.dart';

import 'user_preferences_service.dart';

enum AppLanguage { es, en }

class TranslationService extends ChangeNotifier {
  TranslationService._() : _persistLanguage = _persistProductionLanguage;

  @visibleForTesting
  TranslationService.forTesting(
    Future<void> Function(String language) persistLanguage,
  ) : _persistLanguage = persistLanguage;

  static final TranslationService instance = TranslationService._();

  UserPreferencesService get _userPreferencesService =>
      UserPreferencesService.instance;
  final Future<void> Function(String language) _persistLanguage;

  static Future<void> _persistProductionLanguage(String language) {
    return UserPreferencesService.instance.setLanguage(language);
  }

  AppLanguage _currentLanguage = AppLanguage.es;
  bool _savingLanguage = false;
  int _stateVersion = 0;

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

    applyUserPreference(preferences.language, notify: notify);
  }

  void applyUserPreference(String language, {bool notify = true}) {
    final AppLanguage newLanguage = language == 'en'
        ? AppLanguage.en
        : AppLanguage.es;
    final bool changed = _currentLanguage != newLanguage;
    _stateVersion += 1;
    _savingLanguage = false;
    _currentLanguage = newLanguage;
    if (notify && changed) {
      notifyListeners();
    }
  }

  // =========================================================
  // CAMBIAR IDIOMA
  // =========================================================

  Future<void> changeLanguage(AppLanguage language) async {
    if (_currentLanguage == language || _savingLanguage) {
      return;
    }

    // Cambio inmediato en pantalla.
    final AppLanguage previousLanguage = _currentLanguage;
    _savingLanguage = true;
    final int operationVersion = ++_stateVersion;
    _currentLanguage = language;

    notifyListeners();

    // Persistencia exclusiva para el UID activo.
    try {
      await _persistLanguage(language.name);
    } catch (_) {
      if (_stateVersion == operationVersion) {
        _currentLanguage = previousLanguage;
        notifyListeners();
      }
      rethrow;
    } finally {
      if (_stateVersion == operationVersion) {
        _savingLanguage = false;
      }
    }
  }

  Future<void> toggleLanguage() async {
    await changeLanguage(isSpanish ? AppLanguage.en : AppLanguage.es);
  }

  // =========================================================
  // CERRAR SESIÓN
  // =========================================================

  void resetForSignedOutUser() {
    _stateVersion += 1;
    _savingLanguage = false;
    if (_currentLanguage == AppLanguage.es) {
      return;
    }

    _currentLanguage = AppLanguage.es;

    notifyListeners();
  }
}
