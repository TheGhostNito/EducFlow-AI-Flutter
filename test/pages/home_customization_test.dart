import 'package:eduflow_ai/pages/dashboard/widgets/home_content_sections.dart';
import 'package:eduflow_ai/pages/settings/home_customization_page.dart';
import 'package:eduflow_ai/pages/settings/settings_page.dart';
import 'package:eduflow_ai/services/home_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const String uid = 'home-customization-test';
  final HomePreferencesService service = HomePreferencesService.instance;

  setUpAll(() async {
    await FirebaseAuthTestHost().initialize(initialUid: uid);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service.clearMemoryCache();
  });

  Future<void> pumpPage(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(theme: ThemeData(useMaterial3: true), home: home),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('Ajustes abre Personalizar Inicio', (tester) async {
    await pumpPage(tester, const SettingsPage());

    final Finder entry = find.byKey(const Key('open-home-customization'));
    await tester.scrollUntilVisible(entry, 160);
    await tester.tap(entry);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(HomeCustomizationPage), findsOneWidget);
    expect(find.text('INFORMACIÓN ACADÉMICA'), findsOneWidget);
  });

  testWidgets('los interruptores actualizan su estado', (tester) async {
    await pumpPage(tester, const HomeCustomizationPage());
    final Finder toggle = find.byKey(const Key('home-classes-switch'));

    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.ensureVisible(toggle);
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, 150));
    await tester.pump();
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(toggle);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });

  testWidgets('Inicio oculta y vuelve a mostrar una sección', (tester) async {
    Widget host(HomePreferences preferences) {
      return MaterialApp(
        home: Scaffold(
          body: HomeContentSections(
            preferences: preferences,
            summary: const Text('resumen-inicio'),
            todayClasses: const Text('clases-inicio'),
            subjects: const Text('asignaturas-inicio'),
          ),
        ),
      );
    }

    await tester.pumpWidget(
      host(HomePreferences.defaults.copyWith(todayClassesVisible: false)),
    );
    expect(find.text('clases-inicio'), findsNothing);
    expect(find.text('resumen-inicio'), findsOneWidget);
    expect(find.text('asignaturas-inicio'), findsOneWidget);

    await tester.pumpWidget(host(HomePreferences.defaults));
    expect(find.text('clases-inicio'), findsOneWidget);
  });

  test('las preferencias se mantienen en almacenamiento local', () async {
    const HomePreferences saved = HomePreferences(
      summaryVisible: false,
      todayClassesVisible: true,
      subjectsVisible: false,
      nextTaskVisible: false,
      nextEvaluationVisible: true,
      studyRemindersVisible: false,
      smartSummaryVisible: true,
    );
    await service.saveForUser(uid, saved);
    service.clearMemoryCache();

    final HomePreferences loaded = await service.loadForUser(uid);
    expect(loaded, saved);
  });

  testWidgets('Restablecer Inicio recupera los valores predeterminados', (
    tester,
  ) async {
    await service.saveForUser(
      uid,
      const HomePreferences(
        summaryVisible: false,
        todayClassesVisible: false,
        subjectsVisible: false,
        nextTaskVisible: false,
        nextEvaluationVisible: false,
        studyRemindersVisible: false,
        smartSummaryVisible: false,
      ),
    );
    await pumpPage(tester, const HomeCustomizationPage());

    expect(
      tester.widget<Switch>(find.byKey(const Key('home-summary-switch'))).value,
      isFalse,
    );

    final Finder reset = find.byKey(const Key('reset-home'));
    await tester.ensureVisible(reset);
    await tester.pump();
    await tester.tap(reset);
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-reset-home')));
    await tester.pump();

    for (final String key in [
      'home-summary-switch',
      'home-classes-switch',
      'home-subjects-switch',
      'home-next-task-switch',
      'home-next-evaluation-switch',
      'home-smart-summary-switch',
    ]) {
      expect(tester.widget<Switch>(find.byKey(Key(key))).value, isTrue);
    }

    service.clearMemoryCache();
    expect(await service.loadForUser(uid), HomePreferences.defaults);
  });

  testWidgets('muestra solo opciones con funcionalidad disponible', (
    tester,
  ) async {
    await pumpPage(tester, const HomeCustomizationPage());
    for (final String label in [
      'Próxima tarea',
      'Próxima evaluación',
      'Resumen inteligente',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Recordatorios de estudio'), findsNothing);
  });

  testWidgets('una sección nueva desactivada no se renderiza', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeContentSections(
          preferences: HomePreferences.defaults.copyWith(
            nextTaskVisible: false,
          ),
          nextTask: const Text('tarea-contextual'),
        ),
      ),
    );
    expect(find.text('tarea-contextual'), findsNothing);
  });

  testWidgets('una sección activada sin datos no ocupa espacio', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: HomeContentSections(preferences: HomePreferences.defaults),
        ),
      ),
    );
    expect(tester.getSize(find.byType(HomeContentSections)), Size.zero);
  });

  testWidgets('ocultar todo muestra un estado vacío con acceso directo', (
    tester,
  ) async {
    final HomePreferences hidden = HomePreferences.defaults.copyWith(
      summaryVisible: false,
      todayClassesVisible: false,
      subjectsVisible: false,
      nextTaskVisible: false,
      nextEvaluationVisible: false,
      smartSummaryVisible: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => HomeContentSections(
            preferences: hidden,
            summary: const Text('resumen'),
            emptyState: FilledButton(
              key: const Key('test-empty-customize'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const HomeCustomizationPage(),
                ),
              ),
              child: const Text('Personalizar Inicio'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Personalizar Inicio'), findsOneWidget);
    await tester.tap(find.byKey(const Key('test-empty-customize')));
    await tester.pumpAndSettle();
    expect(find.byType(HomeCustomizationPage), findsOneWidget);
  });

  testWidgets('al reactivar contenido desaparece el estado vacío', (
    tester,
  ) async {
    Widget host(HomePreferences preferences) => MaterialApp(
      home: HomeContentSections(
        preferences: preferences,
        summary: const Text('resumen-visible'),
        emptyState: const Text('inicio-despejado'),
      ),
    );

    await tester.pumpWidget(
      host(HomePreferences.defaults.copyWith(summaryVisible: false)),
    );
    expect(find.text('inicio-despejado'), findsOneWidget);

    await tester.pumpWidget(host(HomePreferences.defaults));
    expect(find.text('inicio-despejado'), findsNothing);
    expect(find.text('resumen-visible'), findsOneWidget);
  });

  testWidgets('una recomendación válida evita el estado vacío', (tester) async {
    final HomePreferences preferences = HomePreferences.defaults.copyWith(
      summaryVisible: false,
      todayClassesVisible: false,
      subjectsVisible: false,
      nextTaskVisible: false,
      nextEvaluationVisible: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeContentSections(
          preferences: preferences,
          smartSummary: const Text('recomendación-válida'),
          emptyState: const Text('inicio-despejado'),
        ),
      ),
    );

    expect(find.text('recomendación-válida'), findsOneWidget);
    expect(find.text('inicio-despejado'), findsNothing);
  });

  test('Recordarme después oculta solo hasta el siguiente día', () async {
    final DateTime now = DateTime(2026, 9, 7, 15);
    await service.dismissInsightForUser(uid, 'task:one', now: now);

    expect(
      await service.isInsightDismissedForUser(
        uid,
        'task:one',
        now: DateTime(2026, 9, 7, 23, 59),
      ),
      isTrue,
    );
    expect(
      await service.isInsightDismissedForUser(
        uid,
        'task:one',
        now: DateTime(2026, 9, 8),
      ),
      isFalse,
    );
  });
}
