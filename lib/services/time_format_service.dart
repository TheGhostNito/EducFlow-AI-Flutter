import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'user_preferences_service.dart';

enum TimeFormatPreference { system, h24, h12 }

class TimeFormatService extends ChangeNotifier with WidgetsBindingObserver {
  TimeFormatService._();

  static final TimeFormatService instance = TimeFormatService._();

  final UserPreferencesService _userPreferencesService =
      UserPreferencesService.instance;

  static const MethodChannel _channel = MethodChannel('educflow/time_format');

  TimeFormatPreference _preference = TimeFormatPreference.system;

  bool _systemUses24Hours = false;

  bool _observerRegistrado = false;

  TimeFormatPreference get preference => _preference;

  // =========================================================
  // INICIALIZACIÓN
  // =========================================================

  Future<void> initialize() async {
    if (!_observerRegistrado) {
      WidgetsBinding.instance.addObserver(this);

      _observerRegistrado = true;
    }

    await _actualizarFormatoSistema(notificar: false);

    await loadCurrentUserPreferences(forceRefresh: false, notify: false);
  }

  // =========================================================
  // CARGAR CUENTA ACTUAL
  // =========================================================

  Future<void> loadCurrentUserPreferences({
    bool forceRefresh = false,
    bool notify = true,
  }) async {
    final String? uid = _userPreferencesService.currentUid;

    // Sin sesión usamos la configuración
    // del dispositivo como opción pública.
    if (uid == null) {
      final bool changed = _preference != TimeFormatPreference.system;

      _preference = TimeFormatPreference.system;

      await _actualizarFormatoSistema(notificar: false);

      if (notify && changed) {
        notifyListeners();
      }

      return;
    }

    final UserPreferences preferences = await _userPreferencesService
        .getPreferencesForUser(uid, forceRefresh: forceRefresh);

    final TimeFormatPreference newPreference = switch (preferences.timeFormat) {
      '24h' => TimeFormatPreference.h24,
      '12h' => TimeFormatPreference.h12,
      _ => TimeFormatPreference.system,
    };

    final bool changed = _preference != newPreference;

    _preference = newPreference;

    if (_preference == TimeFormatPreference.system) {
      await _actualizarFormatoSistema(notificar: false);
    }

    if (notify && changed) {
      notifyListeners();
    }
  }

  // =========================================================
  // CAMBIAR PREFERENCIA
  // =========================================================

  Future<void> setPreference(TimeFormatPreference preference) async {
    final bool changed = _preference != preference;

    _preference = preference;

    if (preference == TimeFormatPreference.system) {
      await _actualizarFormatoSistema(notificar: false);
    }

    if (changed || preference == TimeFormatPreference.system) {
      notifyListeners();
    }

    final String value = switch (preference) {
      TimeFormatPreference.system => 'system',
      TimeFormatPreference.h24 => '24h',
      TimeFormatPreference.h12 => '12h',
    };

    await _userPreferencesService.setTimeFormat(value);
  }

  // =========================================================
  // CONFIGURACIÓN DEL DISPOSITIVO
  // =========================================================

  Future<void> _actualizarFormatoSistema({bool notificar = true}) async {
    bool nuevoValor;

    try {
      final bool? respuesta = await _channel.invokeMethod<bool>(
        'uses24HourFormat',
      );

      nuevoValor =
          respuesta ??
          WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
    } on MissingPluginException {
      nuevoValor =
          WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
    } on PlatformException {
      nuevoValor =
          WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat;
    }

    final bool cambio = nuevoValor != _systemUses24Hours;

    _systemUses24Hours = nuevoValor;

    if (notificar && cambio && _preference == TimeFormatPreference.system) {
      notifyListeners();
    }
  }

  // =========================================================
  // FORMATO ACTUAL
  // =========================================================

  bool use24HourFormat(BuildContext context) {
    switch (_preference) {
      case TimeFormatPreference.h24:
        return true;

      case TimeFormatPreference.h12:
        return false;

      case TimeFormatPreference.system:
        return _systemUses24Hours;
    }
  }

  // =========================================================
  // MOSTRAR HH:mm
  // =========================================================

  String formatStoredTime(BuildContext context, String value) {
    final TimeOfDay? time = _parseStoredTime(value);

    if (time == null) {
      return value;
    }

    return MaterialLocalizations.of(context)
        .formatTimeOfDay(time, alwaysUse24HourFormat: use24HourFormat(context));
  }

  // =========================================================
  // PARSEAR FORMATO INTERNO
  // =========================================================

  TimeOfDay? _parseStoredTime(String value) {
    final List<String> parts = value.split(':');

    if (parts.length != 2) {
      return null;
    }

    final int? hour = int.tryParse(parts[0]);

    final int? minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }

    return TimeOfDay(hour: hour, minute: minute);
  }

  // =========================================================
  // VOLVER DESDE AJUSTES DEL DISPOSITIVO
  // =========================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _preference == TimeFormatPreference.system) {
      _actualizarFormatoSistema();
    }
  }

  // =========================================================
  // CERRAR SESIÓN
  // =========================================================

  Future<void> resetForSignedOutUser() async {
    final bool changed = _preference != TimeFormatPreference.system;

    _preference = TimeFormatPreference.system;

    await _actualizarFormatoSistema(notificar: false);

    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_observerRegistrado) {
      WidgetsBinding.instance.removeObserver(this);
    }

    super.dispose();
  }
}
