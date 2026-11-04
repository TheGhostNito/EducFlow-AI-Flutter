import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show Supabase, SupabaseClient;

@immutable
class HomePreferences {
  const HomePreferences({
    required this.summaryVisible,
    required this.todayClassesVisible,
    required this.subjectsVisible,
    required this.nextTaskVisible,
    required this.nextEvaluationVisible,
    required this.studyRemindersVisible,
    required this.smartSummaryVisible,
  });

  final bool summaryVisible;
  final bool todayClassesVisible;
  final bool subjectsVisible;
  final bool nextTaskVisible;
  final bool nextEvaluationVisible;
  final bool studyRemindersVisible;
  final bool smartSummaryVisible;

  static const HomePreferences defaults = HomePreferences(
    summaryVisible: true,
    todayClassesVisible: true,
    subjectsVisible: true,
    nextTaskVisible: true,
    nextEvaluationVisible: true,
    studyRemindersVisible: true,
    smartSummaryVisible: true,
  );

  factory HomePreferences.fromDatabase(Map<String, dynamic> values) {
    bool read(String key, bool fallback) =>
        values[key] is bool ? values[key] as bool : fallback;
    return HomePreferences(
      summaryVisible: read('resumenAcademico', defaults.summaryVisible),
      todayClassesVisible: read('clasesHoy', defaults.todayClassesVisible),
      subjectsVisible: read('misAsignaturas', defaults.subjectsVisible),
      nextTaskVisible: read('proximaTarea', defaults.nextTaskVisible),
      nextEvaluationVisible: read(
        'proximaEvaluacion',
        defaults.nextEvaluationVisible,
      ),
      studyRemindersVisible: read(
        'recordatoriosEstudio',
        defaults.studyRemindersVisible,
      ),
      smartSummaryVisible: read(
        'resumenInteligente',
        defaults.smartSummaryVisible,
      ),
    );
  }

  Map<String, dynamic> toDatabase() => {
    'resumenAcademico': summaryVisible,
    'clasesHoy': todayClassesVisible,
    'misAsignaturas': subjectsVisible,
    'proximaTarea': nextTaskVisible,
    'proximaEvaluacion': nextEvaluationVisible,
    'recordatoriosEstudio': studyRemindersVisible,
    'resumenInteligente': smartSummaryVisible,
  };

  HomePreferences copyWith({
    bool? summaryVisible,
    bool? todayClassesVisible,
    bool? subjectsVisible,
    bool? nextTaskVisible,
    bool? nextEvaluationVisible,
    bool? studyRemindersVisible,
    bool? smartSummaryVisible,
  }) {
    return HomePreferences(
      summaryVisible: summaryVisible ?? this.summaryVisible,
      todayClassesVisible: todayClassesVisible ?? this.todayClassesVisible,
      subjectsVisible: subjectsVisible ?? this.subjectsVisible,
      nextTaskVisible: nextTaskVisible ?? this.nextTaskVisible,
      nextEvaluationVisible:
          nextEvaluationVisible ?? this.nextEvaluationVisible,
      studyRemindersVisible:
          studyRemindersVisible ?? this.studyRemindersVisible,
      smartSummaryVisible: smartSummaryVisible ?? this.smartSummaryVisible,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HomePreferences &&
        other.summaryVisible == summaryVisible &&
        other.todayClassesVisible == todayClassesVisible &&
        other.subjectsVisible == subjectsVisible &&
        other.nextTaskVisible == nextTaskVisible &&
        other.nextEvaluationVisible == nextEvaluationVisible &&
        other.studyRemindersVisible == studyRemindersVisible &&
        other.smartSummaryVisible == smartSummaryVisible;
  }

  @override
  int get hashCode => Object.hash(
    summaryVisible,
    todayClassesVisible,
    subjectsVisible,
    nextTaskVisible,
    nextEvaluationVisible,
    studyRemindersVisible,
    smartSummaryVisible,
  );
}

abstract interface class HomePreferencesDataSource {
  Future<Map<String, dynamic>?> get(String uid);
  Future<void> insertIfMissing(String uid);
  Future<void> save(String uid, Map<String, dynamic> values);
}

class SupabaseHomePreferencesDataSource implements HomePreferencesDataSource {
  SupabaseHomePreferencesDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<Map<String, dynamic>?> get(String uid) async {
    final row = await _client
        .from('preferencias_usuario')
        .select('configuracion_inicio')
        .eq('usuario_uid', uid)
        .maybeSingle();
    return row?['configuracion_inicio'] is Map
        ? Map<String, dynamic>.from(row!['configuracion_inicio'] as Map)
        : null;
  }

  @override
  Future<void> insertIfMissing(String uid) async {
    await _client
        .from('preferencias_usuario')
        .upsert(
          {'usuario_uid': uid},
          onConflict: 'usuario_uid',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> save(String uid, Map<String, dynamic> values) async {
    await _client
        .from('preferencias_usuario')
        .update({'configuracion_inicio': values})
        .eq('usuario_uid', uid);
  }
}

class HomePreferencesService extends ChangeNotifier {
  HomePreferencesService._();

  static final HomePreferencesService instance = HomePreferencesService._();

  final Map<String, HomePreferences> _memoryCache = {};
  HomePreferencesDataSource? _dataSourceOverride;

  HomePreferencesDataSource get _dataSource =>
      _dataSourceOverride ??
      SupabaseHomePreferencesDataSource(Supabase.instance.client);

  @visibleForTesting
  void useDataSourceForTesting(HomePreferencesDataSource? dataSource) {
    _dataSourceOverride = dataSource;
  }

  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  HomePreferences _current = HomePreferences.defaults;

  HomePreferences get current => _current;

  Future<HomePreferences> loadCurrent({bool forceRefresh = false}) async {
    final String? uid = currentUid;
    if (uid == null) {
      _setCurrent(HomePreferences.defaults, notify: false);
      return _current;
    }

    return loadForUser(uid, forceRefresh: forceRefresh);
  }

  Future<HomePreferences> loadForUser(
    String uid, {
    bool forceRefresh = false,
  }) async {
    if (currentUid != uid) {
      throw StateError('La configuración de Inicio no pertenece a la sesión.');
    }
    final HomePreferences? cached = _memoryCache[uid];
    if (!forceRefresh && cached != null) {
      _setCurrent(cached, notify: false);
      return cached;
    }

    try {
      final remote = await _dataSource.get(uid);
      if (currentUid != uid) throw StateError('La sesión cambió.');
      if (remote != null) {
        final preferences = HomePreferences.fromDatabase(remote);
        _memoryCache[uid] = preferences;
        _setCurrent(preferences, notify: false);
        return preferences;
      }
    } catch (_) {
      if (currentUid != uid) throw StateError('La sesión cambió.');
      // La caché local solo se usa cuando SQL no puede responder.
    }

    final SharedPreferences local = await SharedPreferences.getInstance();
    final HomePreferences preferences = HomePreferences(
      summaryVisible:
          local.getBool(_key(uid, 'summary-visible')) ??
          HomePreferences.defaults.summaryVisible,
      todayClassesVisible:
          local.getBool(_key(uid, 'today-classes-visible')) ??
          HomePreferences.defaults.todayClassesVisible,
      subjectsVisible:
          local.getBool(_key(uid, 'subjects-visible')) ??
          HomePreferences.defaults.subjectsVisible,
      nextTaskVisible:
          local.getBool(_key(uid, 'next-task-visible')) ??
          HomePreferences.defaults.nextTaskVisible,
      nextEvaluationVisible:
          local.getBool(_key(uid, 'next-evaluation-visible')) ??
          HomePreferences.defaults.nextEvaluationVisible,
      studyRemindersVisible:
          local.getBool(_key(uid, 'study-reminders-visible')) ??
          HomePreferences.defaults.studyRemindersVisible,
      smartSummaryVisible:
          local.getBool(_key(uid, 'smart-summary-visible')) ??
          HomePreferences.defaults.smartSummaryVisible,
    );

    _memoryCache[uid] = preferences;
    _setCurrent(preferences, notify: false);
    return preferences;
  }

  Future<void> saveCurrent(HomePreferences preferences) async {
    final String? uid = currentUid;
    if (uid == null) return;

    await saveForUser(uid, preferences);
  }

  Future<void> saveForUser(String uid, HomePreferences preferences) async {
    if (currentUid != uid) throw StateError('La sesión cambió.');
    await _dataSource.insertIfMissing(uid);
    if (currentUid != uid) throw StateError('La sesión cambió.');
    final remote = await _dataSource.get(uid);
    if (currentUid != uid) throw StateError('La sesión cambió.');
    await _dataSource.save(uid, {...?remote, ...preferences.toDatabase()});
    if (currentUid != uid) throw StateError('La sesión cambió.');
    final SharedPreferences local = await SharedPreferences.getInstance();
    await Future.wait([
      local.setBool(_key(uid, 'summary-visible'), preferences.summaryVisible),
      local.setBool(
        _key(uid, 'today-classes-visible'),
        preferences.todayClassesVisible,
      ),
      local.setBool(_key(uid, 'subjects-visible'), preferences.subjectsVisible),
      local.setBool(
        _key(uid, 'next-task-visible'),
        preferences.nextTaskVisible,
      ),
      local.setBool(
        _key(uid, 'next-evaluation-visible'),
        preferences.nextEvaluationVisible,
      ),
      local.setBool(
        _key(uid, 'study-reminders-visible'),
        preferences.studyRemindersVisible,
      ),
      local.setBool(
        _key(uid, 'smart-summary-visible'),
        preferences.smartSummaryVisible,
      ),
    ]);

    _memoryCache[uid] = preferences;
    _setCurrent(preferences);
  }

  Future<void> resetCurrent() async {
    await saveCurrent(HomePreferences.defaults);
  }

  Future<void> dismissInsightUntilTomorrow(String insightId) async {
    final String? uid = currentUid;
    if (uid == null) return;
    await dismissInsightForUser(uid, insightId, now: DateTime.now());
  }

  Future<void> dismissInsightForUser(
    String uid,
    String insightId, {
    required DateTime now,
  }) async {
    final SharedPreferences local = await SharedPreferences.getInstance();
    final DateTime tomorrow = DateTime(now.year, now.month, now.day + 1);
    await Future.wait([
      local.setString(_key(uid, 'dismissed-insight-id'), insightId),
      local.setString(
        _key(uid, 'dismissed-insight-until'),
        tomorrow.toIso8601String(),
      ),
    ]);
  }

  Future<bool> isInsightDismissed(String insightId, {DateTime? now}) async {
    final String? uid = currentUid;
    if (uid == null) return false;
    return isInsightDismissedForUser(
      uid,
      insightId,
      now: now ?? DateTime.now(),
    );
  }

  Future<bool> isInsightDismissedForUser(
    String uid,
    String insightId, {
    required DateTime now,
  }) async {
    final SharedPreferences local = await SharedPreferences.getInstance();
    final String? dismissedId = local.getString(
      _key(uid, 'dismissed-insight-id'),
    );
    final DateTime? until = DateTime.tryParse(
      local.getString(_key(uid, 'dismissed-insight-until')) ?? '',
    );
    return dismissedId == insightId && until != null && now.isBefore(until);
  }

  String _key(String uid, String preference) {
    return 'educflow-user-$uid-home-$preference';
  }

  void _setCurrent(HomePreferences preferences, {bool notify = true}) {
    final bool changed = _current != preferences;
    _current = preferences;
    if (notify && changed) notifyListeners();
  }

  void clearMemoryCache() {
    _memoryCache.clear();
    _current = HomePreferences.defaults;
  }
}
