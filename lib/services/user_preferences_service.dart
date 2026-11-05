import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

class NotificationPreferences {
  const NotificationPreferences({
    required this.enabled,
    required this.classesEnabled,
    required this.classLeadMinutes,
    required this.tasksEnabled,
    required this.taskReminderTime,
    required this.evaluationsEnabled,
    required this.evaluationReminderTime,
  });

  final bool enabled;
  final bool classesEnabled;
  final int classLeadMinutes;
  final bool tasksEnabled;
  final String taskReminderTime;
  final bool evaluationsEnabled;
  final String evaluationReminderTime;

  static const NotificationPreferences defaults = NotificationPreferences(
    enabled: true,
    classesEnabled: true,
    classLeadMinutes: 30,
    tasksEnabled: true,
    taskReminderTime: '18:00',
    evaluationsEnabled: true,
    evaluationReminderTime: '18:00',
  );

  NotificationPreferences copyWith({
    bool? enabled,
    bool? classesEnabled,
    int? classLeadMinutes,
    bool? tasksEnabled,
    String? taskReminderTime,
    bool? evaluationsEnabled,
    String? evaluationReminderTime,
  }) {
    return NotificationPreferences(
      enabled: enabled ?? this.enabled,
      classesEnabled: classesEnabled ?? this.classesEnabled,
      classLeadMinutes: classLeadMinutes ?? this.classLeadMinutes,
      tasksEnabled: tasksEnabled ?? this.tasksEnabled,
      taskReminderTime: taskReminderTime ?? this.taskReminderTime,
      evaluationsEnabled: evaluationsEnabled ?? this.evaluationsEnabled,
      evaluationReminderTime:
          evaluationReminderTime ?? this.evaluationReminderTime,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'activadas': enabled,
      'clases': classesEnabled,
      'minutosAntesClase': classLeadMinutes,
      'tareas': tasksEnabled,
      'horaTareas': taskReminderTime,
      'evaluaciones': evaluationsEnabled,
      'horaEvaluaciones': evaluationReminderTime,
    };
  }

  factory NotificationPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return defaults;
    }

    final int rawLead =
        int.tryParse(map['minutosAntesClase']?.toString() ?? '') ??
        defaults.classLeadMinutes;

    final int lead = switch (rawLead) {
      15 => 15,
      60 => 60,
      _ => 30,
    };

    return NotificationPreferences(
      enabled: map['activadas'] as bool? ?? defaults.enabled,
      classesEnabled: map['clases'] as bool? ?? defaults.classesEnabled,
      classLeadMinutes: lead,
      tasksEnabled: map['tareas'] as bool? ?? defaults.tasksEnabled,
      taskReminderTime: _validTime(
        map['horaTareas']?.toString(),
        defaults.taskReminderTime,
      ),
      evaluationsEnabled:
          map['evaluaciones'] as bool? ?? defaults.evaluationsEnabled,
      evaluationReminderTime: _validTime(
        map['horaEvaluaciones']?.toString(),
        defaults.evaluationReminderTime,
      ),
    );
  }

  static String _validTime(String? value, String fallback) {
    final String clean = value?.trim() ?? '';
    final RegExp pattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
    return pattern.hasMatch(clean) ? clean : fallback;
  }
}

class UserPreferences {
  const UserPreferences({
    required this.theme,
    required this.language,
    required this.timeFormat,
    required this.notifications,
  });

  final String theme;
  final String language;
  final String timeFormat;
  final NotificationPreferences notifications;

  static const UserPreferences defaults = UserPreferences(
    theme: 'light',
    language: 'es',
    timeFormat: 'system',
    notifications: NotificationPreferences.defaults,
  );

  UserPreferences copyWith({
    String? theme,
    String? language,
    String? timeFormat,
    NotificationPreferences? notifications,
  }) {
    return UserPreferences(
      theme: theme ?? this.theme,
      language: language ?? this.language,
      timeFormat: timeFormat ?? this.timeFormat,
      notifications: notifications ?? this.notifications,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tema': theme,
      'idioma': language,
      'formatoHora': timeFormat,
      'notificaciones': notifications.toMap(),
    };
  }

  factory UserPreferences.fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return defaults;
    }

    final String theme = map['tema']?.toString() ?? 'light';
    final String language = map['idioma']?.toString() ?? 'es';
    final String timeFormat = map['formatoHora']?.toString() ?? 'system';

    final dynamic rawNotifications = map['notificaciones'];

    final NotificationPreferences notifications = rawNotifications is Map
        ? NotificationPreferences.fromMap(
            Map<String, dynamic>.from(rawNotifications),
          )
        : NotificationPreferences.defaults;

    return UserPreferences(
      theme: theme == 'dark' ? 'dark' : 'light',
      language: language == 'en' ? 'en' : 'es',
      timeFormat: switch (timeFormat) {
        '24h' => '24h',
        '12h' => '12h',
        _ => 'system',
      },
      notifications: notifications,
    );
  }

  factory UserPreferences.fromDatabase(Map<String, dynamic> row) {
    return UserPreferences.fromMap({
      'tema': row['tema'],
      'idioma': row['idioma'],
      'formatoHora': row['formato_hora'],
      'notificaciones': {
        'activadas': row['notificaciones_activadas'],
        'clases': row['notificaciones_clases'],
        'minutosAntesClase': row['minutos_antes_clase'],
        'tareas': row['notificaciones_tareas'],
        'horaTareas': _databaseTime(row['hora_tareas']),
        'evaluaciones': row['notificaciones_evaluaciones'],
        'horaEvaluaciones': _databaseTime(row['hora_evaluaciones']),
      },
    });
  }

  static String? _databaseTime(Object? value) {
    final raw = value?.toString();
    return raw == null || raw.length < 5 ? raw : raw.substring(0, 5);
  }
}

abstract interface class UserPreferencesDataSource {
  Future<Map<String, dynamic>?> get(String uid);
  Future<void> insertIfMissing(Map<String, dynamic> values);
  Future<void> update(String uid, Map<String, dynamic> values);
}

class SupabaseUserPreferencesDataSource implements UserPreferencesDataSource {
  SupabaseUserPreferencesDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> get(String uid) async {
    final row = await _client
        .from('preferencias_usuario')
        .select()
        .eq('usuario_uid', uid)
        .maybeSingle();
    return row == null ? null : Map<String, dynamic>.from(row);
  }

  @override
  Future<void> insertIfMissing(Map<String, dynamic> values) async {
    await _client
        .from('preferencias_usuario')
        .upsert(values, onConflict: 'usuario_uid', ignoreDuplicates: true);
  }

  @override
  Future<void> update(String uid, Map<String, dynamic> values) async {
    await _client
        .from('preferencias_usuario')
        .update(values)
        .eq('usuario_uid', uid);
  }
}

class UserPreferencesService extends ChangeNotifier {
  UserPreferencesService({
    UserPreferencesDataSource? dataSource,
    this._auth,
    this._uidProvider,
  }) : _dataSourceOverride = dataSource;

  static final UserPreferencesService instance = UserPreferencesService();

  UserPreferencesDataSource? _dataSourceOverride;
  UserPreferencesDataSource get _dataSource =>
      _dataSourceOverride ??
      SupabaseUserPreferencesDataSource(Supabase.instance.client);

  @visibleForTesting
  void useDataSourceForTesting(UserPreferencesDataSource? dataSource) {
    _dataSourceOverride = dataSource;
    _memoryCache.clear();
  }

  final FirebaseAuth? _auth;
  final String? Function()? _uidProvider;
  final Map<String, UserPreferences> _memoryCache = {};

  User? get currentUser => (_auth ?? FirebaseAuth.instance).currentUser;
  String? get currentUid => _uidProvider?.call() ?? currentUser?.uid;

  Future<UserPreferences> getCurrentPreferences({
    bool forceRefresh = false,
  }) async {
    final String? uid = currentUid;

    if (uid == null) {
      return UserPreferences.defaults;
    }

    return getPreferencesForUser(uid, forceRefresh: forceRefresh);
  }

  Future<UserPreferences> getPreferencesForUser(
    String uid, {
    bool forceRefresh = false,
  }) async {
    if (currentUid != uid) {
      throw StateError('Las preferencias no pertenecen a la sesión activa.');
    }
    if (!forceRefresh) {
      final UserPreferences? memory = _memoryCache[uid];

      if (memory != null) {
        return memory;
      }
    }

    try {
      final row = await _dataSource.get(uid);
      if (currentUid != uid) {
        throw StateError('La sesión cambió durante la lectura.');
      }
      if (row != null) {
        final preferences = UserPreferences.fromDatabase(row);
        _memoryCache[uid] = preferences;
        try {
          await _saveLocalCache(uid, preferences);
        } catch (_) {
          // SQL sigue siendo la fuente de verdad.
        }
        return preferences;
      }
    } catch (_) {
      // Si SQL falla, intentamos usar la caché local de esta cuenta.
    }

    if (currentUid != uid) {
      throw StateError('La sesión cambió durante la lectura.');
    }

    final UserPreferences? local = await _readLocalCache(uid);

    if (local != null) {
      _memoryCache[uid] = local;
      return local;
    }

    return UserPreferences.defaults;
  }

  Future<void> setTheme(String theme) async {
    final String? uid = currentUid;
    if (uid == null) return;
    final UserPreferences current = await getPreferencesForUser(uid);
    final value = theme == 'dark' ? 'dark' : 'light';
    await _saveFields(uid, {'tema': value}, current.copyWith(theme: value));
  }

  Future<void> setLanguage(String language) async {
    final String? uid = currentUid;
    if (uid == null) return;
    final UserPreferences current = await getPreferencesForUser(uid);
    final value = language == 'en' ? 'en' : 'es';
    await _saveFields(uid, {
      'idioma': value,
    }, current.copyWith(language: value));
  }

  Future<void> setTimeFormat(String timeFormat) async {
    final String? uid = currentUid;
    if (uid == null) return;

    final UserPreferences current = await getPreferencesForUser(uid);

    final String value = switch (timeFormat) {
      '24h' => '24h',
      '12h' => '12h',
      _ => 'system',
    };

    await _saveFields(uid, {
      'formato_hora': value,
    }, current.copyWith(timeFormat: value));
  }

  Future<void> setNotificationPreferences(
    NotificationPreferences preferences,
  ) async {
    final String? uid = currentUid;
    if (uid == null) return;

    final UserPreferences current = await getPreferencesForUser(uid);

    await _saveFields(uid, {
      'notificaciones_activadas': preferences.enabled,
      'notificaciones_clases': preferences.classesEnabled,
      'minutos_antes_clase': preferences.classLeadMinutes,
      'notificaciones_tareas': preferences.tasksEnabled,
      'hora_tareas': preferences.taskReminderTime,
      'notificaciones_evaluaciones': preferences.evaluationsEnabled,
      'hora_evaluaciones': preferences.evaluationReminderTime,
    }, current.copyWith(notifications: preferences));
  }

  Future<void> ensureInitialRow({
    required String uid,
    required UserPreferences initialPreferences,
  }) async {
    if (currentUid != uid) {
      throw StateError('Las preferencias no pertenecen a la sesión activa.');
    }
    await _dataSource.insertIfMissing({
      'usuario_uid': uid,
      'tema': initialPreferences.theme,
      'idioma': initialPreferences.language,
    });
    if (currentUid != uid) {
      throw StateError('La sesión cambió durante la preparación.');
    }
    await getPreferencesForUser(uid, forceRefresh: true);
  }

  Future<void> _saveFields(
    String uid,
    Map<String, dynamic> fields,
    UserPreferences preferences,
  ) async {
    if (currentUid != uid) throw StateError('La sesión cambió.');
    await _dataSource.insertIfMissing({'usuario_uid': uid});
    if (currentUid != uid) throw StateError('La sesión cambió.');
    await _dataSource.update(uid, fields);
    if (currentUid != uid) throw StateError('La sesión cambió.');
    _memoryCache[uid] = preferences;
    notifyListeners();
    try {
      await _saveLocalCache(uid, preferences);
    } catch (_) {
      // Una caché local defectuosa no revierte una escritura SQL confirmada.
    }
  }

  String _localKey(String uid, String preference) {
    return 'educflow-user-$uid-$preference';
  }

  Future<void> _saveLocalCache(String uid, UserPreferences preferences) async {
    final SharedPreferences local = await SharedPreferences.getInstance();
    final NotificationPreferences n = preferences.notifications;

    await Future.wait([
      local.setString(_localKey(uid, 'theme'), preferences.theme),
      local.setString(_localKey(uid, 'language'), preferences.language),
      local.setString(_localKey(uid, 'time-format'), preferences.timeFormat),
      local.setBool(_localKey(uid, 'notifications-enabled'), n.enabled),
      local.setBool(_localKey(uid, 'notifications-classes'), n.classesEnabled),
      local.setInt(
        _localKey(uid, 'notifications-class-lead'),
        n.classLeadMinutes,
      ),
      local.setBool(_localKey(uid, 'notifications-tasks'), n.tasksEnabled),
      local.setString(
        _localKey(uid, 'notifications-task-time'),
        n.taskReminderTime,
      ),
      local.setBool(
        _localKey(uid, 'notifications-evaluations'),
        n.evaluationsEnabled,
      ),
      local.setString(
        _localKey(uid, 'notifications-evaluation-time'),
        n.evaluationReminderTime,
      ),
    ]);
  }

  Future<UserPreferences?> _readLocalCache(String uid) async {
    final SharedPreferences local = await SharedPreferences.getInstance();

    final String? theme = local.getString(_localKey(uid, 'theme'));
    final String? language = local.getString(_localKey(uid, 'language'));
    final String? timeFormat = local.getString(_localKey(uid, 'time-format'));

    final bool? notificationsEnabled = local.getBool(
      _localKey(uid, 'notifications-enabled'),
    );

    final bool? classesEnabled = local.getBool(
      _localKey(uid, 'notifications-classes'),
    );

    final int? classLead = local.getInt(
      _localKey(uid, 'notifications-class-lead'),
    );

    final bool? tasksEnabled = local.getBool(
      _localKey(uid, 'notifications-tasks'),
    );

    final String? taskTime = local.getString(
      _localKey(uid, 'notifications-task-time'),
    );

    final bool? evaluationsEnabled = local.getBool(
      _localKey(uid, 'notifications-evaluations'),
    );

    final String? evaluationTime = local.getString(
      _localKey(uid, 'notifications-evaluation-time'),
    );

    final bool hasAny =
        theme != null ||
        language != null ||
        timeFormat != null ||
        notificationsEnabled != null ||
        classesEnabled != null ||
        classLead != null ||
        tasksEnabled != null ||
        taskTime != null ||
        evaluationsEnabled != null ||
        evaluationTime != null;

    if (!hasAny) {
      return null;
    }

    return UserPreferences.fromMap({
      'tema': theme,
      'idioma': language,
      'formatoHora': timeFormat,
      'notificaciones': {
        'activadas': notificationsEnabled,
        'clases': classesEnabled,
        'minutosAntesClase': classLead,
        'tareas': tasksEnabled,
        'horaTareas': taskTime,
        'evaluaciones': evaluationsEnabled,
        'horaEvaluaciones': evaluationTime,
      },
    });
  }

  void clearMemoryCache() {
    _memoryCache.clear();
  }

  void clearUserFromMemory(String uid) {
    _memoryCache.remove(uid);
  }
}
