import 'package:eduflow_ai/core/navigation/main_navigation.dart';
import 'package:eduflow_ai/services/notification_service.dart';
import 'package:eduflow_ai/widgets/main_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ionicons/ionicons.dart';

import '../support/firebase_auth_test_host.dart';

class _Routes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.remove(route);
}

class _Section extends StatelessWidget {
  const _Section(this.section, this.payload);
  final SeccionPrincipal section;
  final String? payload;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        Column(
          children: [
            Text('seccion:${section.name}'),
            if (payload != null) Text(payload!),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _Secondary('Perfil'),
                ),
              ),
              child: const Text('Abrir Perfil'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const _Secondary('Asignaturas'),
                ),
              ),
              child: const Text('Abrir Asignaturas'),
            ),
          ],
        ),
        MainBottomNav(
          currentIndex: section.index,
          onHome: () => MainNavigation.goTo(context, SeccionPrincipal.inicio),
          onSchedule: () =>
              MainNavigation.goTo(context, SeccionPrincipal.horario),
          onAi: () => MainNavigation.goTo(context, SeccionPrincipal.ia),
          onCalendar: () =>
              MainNavigation.goTo(context, SeccionPrincipal.calendario),
          onNotifications: () =>
              MainNavigation.goTo(context, SeccionPrincipal.notificaciones),
        ),
      ],
    ),
  );
}

class _Secondary extends StatelessWidget {
  const _Secondary(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(name)),
    body: TextButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const _Secondary('Detalle')),
      ),
      child: const Text('Abrir detalle'),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FirebaseAuthTestHost().initialize);
  final payloads = NotificationService.instance.notificationPayload;
  setUp(() => payloads.value = null);
  tearDown(() => payloads.value = null);

  Future<_Routes> mostrar(
    WidgetTester tester, {
    bool? isWebOverride,
    MainSectionBuilder? sectionBuilder,
  }) async {
    final observer = _Routes();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: MainNavigation(
          isWebOverride: isWebOverride,
          sectionBuilder:
              sectionBuilder ??
              (_, section, payload) => _Section(section, payload),
        ),
      ),
    );
    // MainBottomNav incluye una animación continua del botón IA.
    await tester.pump(const Duration(milliseconds: 400));
    return observer;
  }

  Future<void> pulsar(WidgetTester tester, IconData icon) async {
    await tester.tap(find.byIcon(icon));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('PWA: Inicio → Horario → Inicio → Atrás no reconstruye Inicio', (
    tester,
  ) async {
    var salidas = 0;
    var construccionesInicio = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') salidas++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final observer = await mostrar(
      tester,
      isWebOverride: true,
      sectionBuilder: (_, section, payload) {
        if (section == SeccionPrincipal.inicio) construccionesInicio++;
        return _Section(section, payload);
      },
    );
    await pulsar(tester, Ionicons.timeOutline);
    expect(find.text('seccion:horario'), findsOneWidget);
    await pulsar(tester, Ionicons.home);
    expect(observer.routes, hasLength(1));
    expect(construccionesInicio, 2);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('seccion:inicio'), findsOneWidget);
    expect(find.text('seccion:horario'), findsNothing);
    expect(construccionesInicio, 2);
    expect(observer.routes, hasLength(1));
    expect(salidas, 0);
  });

  testWidgets('Android delega Atrás al sistema desde Inicio', (tester) async {
    var salidas = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemNavigator.pop') salidas++;
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mostrar(tester, isWebOverride: false);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(salidas, 1);
  });

  testWidgets('las cinco secciones comparten una ruta y Atrás vuelve a Inicio', (
    tester,
  ) async {
    final observer = await mostrar(tester);
    for (final icon in [
      Ionicons.timeOutline,
      Ionicons.calendarClearOutline,
      Ionicons.notificationsOutline,
    ]) {
      await pulsar(tester, icon);
      expect(observer.routes, hasLength(1));
    }
    // El botón IA tiene su propio dibujo; se usa el callback real de la barra.
    tester.widget<MainBottomNav>(find.byType(MainBottomNav)).onAi();
    await tester.pump();
    expect(find.text('seccion:ia'), findsOneWidget);
    expect(observer.routes, hasLength(1));
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('seccion:inicio'), findsOneWidget);
    expect(observer.routes, hasLength(1));
  });

  testWidgets('Perfil y Asignaturas → Detalle conservan su pila secundaria', (
    tester,
  ) async {
    final observer = await mostrar(tester);
    await tester.tap(find.text('Abrir Perfil'));
    await tester.pumpAndSettle();
    expect(observer.routes, hasLength(2));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('seccion:inicio'), findsOneWidget);
    await tester.tap(find.text('Abrir Asignaturas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir detalle'));
    await tester.pumpAndSettle();
    expect(observer.routes, hasLength(3));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Asignaturas'), findsOneWidget);
    expect(observer.routes, hasLength(2));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(observer.routes, hasLength(1));
  });

  testWidgets('las notificaciones seleccionan su sección sin apilarla', (
    tester,
  ) async {
    final observer = await mostrar(tester);
    await pulsar(tester, Ionicons.timeOutline);
    payloads.value = 'academic|tarea|ejemplo';
    await tester.pump();
    await tester.pump();
    expect(find.text('seccion:notificaciones'), findsOneWidget);
    expect(find.text('academic|tarea|ejemplo'), findsOneWidget);
    expect(observer.routes, hasLength(1));
    expect(payloads.value, isNull);
    await pulsar(tester, Ionicons.home);
    payloads.value = 'general';
    await tester.pump();
    expect(find.text('seccion:inicio'), findsOneWidget);
    expect(payloads.value, isNull);
  });

  testWidgets('una notificación no elimina un formulario secundario abierto', (
    tester,
  ) async {
    final observer = await mostrar(tester);
    await tester.tap(find.text('Abrir Perfil'));
    await tester.pumpAndSettle();
    payloads.value = 'academic|clase|ejemplo';
    await tester.pump();
    await tester.pump();
    expect(find.text('Perfil'), findsOneWidget);
    expect(observer.routes, hasLength(2));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('seccion:notificaciones'), findsOneWidget);
  });
}
