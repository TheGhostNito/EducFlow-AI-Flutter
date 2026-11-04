import 'package:eduflow_ai/services/user_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const uid = 'firebase-user-a';
  String? currentUid = uid;
  late _FakePreferencesDataSource dataSource;
  late UserPreferencesService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    currentUid = uid;
    dataSource = _FakePreferencesDataSource();
    service = UserPreferencesService(
      dataSource: dataSource,
      uidProvider: () => currentUid,
    );
  });

  test('lee las preferencias SQL y normaliza horas TIME', () async {
    dataSource.rows[uid] = {
      'usuario_uid': uid,
      'tema': 'dark',
      'idioma': 'en',
      'formato_hora': '24h',
      'notificaciones_activadas': false,
      'hora_tareas': '07:30:00',
      'hora_evaluaciones': '19:15:00',
    };
    final result = await service.getPreferencesForUser(uid);
    expect(result.theme, 'dark');
    expect(result.language, 'en');
    expect(result.notifications.enabled, isFalse);
    expect(result.notifications.taskReminderTime, '07:30');
    expect(result.notifications.evaluationReminderTime, '19:15');
  });

  test('la preparación no sobrescribe elecciones SQL existentes', () async {
    dataSource.rows[uid] = {
      'usuario_uid': uid,
      'tema': 'dark',
      'idioma': 'en',
      'formato_hora': '12h',
    };
    await service.ensureInitialRow(
      uid: uid,
      initialPreferences: UserPreferences.defaults,
    );
    expect(dataSource.rows[uid]?['tema'], 'dark');
    expect(dataSource.rows[uid]?['idioma'], 'en');
  });

  test('cambiar tema actualiza solo su columna', () async {
    dataSource.rows[uid] = {
      'usuario_uid': uid,
      'tema': 'light',
      'idioma': 'en',
      'formato_hora': '12h',
    };
    await service.setTheme('dark');
    expect(dataSource.lastUpdate, {'tema': 'dark'});
    expect(dataSource.rows[uid]?['idioma'], 'en');
    expect(dataSource.rows[uid]?['formato_hora'], '12h');
  });

  test('no permite consultar ni escribir otro UID', () async {
    await expectLater(
      service.getPreferencesForUser('other-user'),
      throwsStateError,
    );
    currentUid = 'other-user';
    await expectLater(
      service.ensureInitialRow(
        uid: uid,
        initialPreferences: UserPreferences.defaults,
      ),
      throwsStateError,
    );
    expect(dataSource.rows, isEmpty);
  });
}

class _FakePreferencesDataSource implements UserPreferencesDataSource {
  final rows = <String, Map<String, dynamic>>{};
  Map<String, dynamic>? lastUpdate;

  @override
  Future<Map<String, dynamic>?> get(String uid) async =>
      rows[uid] == null ? null : Map<String, dynamic>.from(rows[uid]!);

  @override
  Future<void> insertIfMissing(Map<String, dynamic> values) async {
    final uid = values['usuario_uid'] as String;
    rows.putIfAbsent(
      uid,
      () => {
        'usuario_uid': uid,
        'tema': 'light',
        'idioma': 'es',
        'formato_hora': 'system',
        ...values,
      },
    );
  }

  @override
  Future<void> update(String uid, Map<String, dynamic> values) async {
    lastUpdate = Map<String, dynamic>.from(values);
    rows[uid]?.addAll(values);
  }
}
