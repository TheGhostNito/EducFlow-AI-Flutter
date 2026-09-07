import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class HomePreferencesService extends ChangeNotifier {
  HomePreferencesService._();

  static final HomePreferencesService instance = HomePreferencesService._();

  final Map<String, HomePreferences> _memoryCache = {};

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
    final HomePreferences? cached = _memoryCache[uid];
    if (!forceRefresh && cached != null) {
      _setCurrent(cached, notify: false);
      return cached;
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

  @visibleForTesting
  void clearMemoryCache() {
    _memoryCache.clear();
    _current = HomePreferences.defaults;
  }
}
