import 'dart:async';

import 'package:eduflow_ai/core/auth/auth_gate.dart';
import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/core/navigation/main_navigation.dart';
import 'package:eduflow_ai/pages/dashboard/dashboard_page.dart';
import 'package:eduflow_ai/pages/login/login_page.dart';
import 'package:eduflow_ai/services/beta_notice_service.dart';
import 'package:eduflow_ai/services/perfil_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FirebaseAuthTestHost().initialize);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SessionUserIdentity identity(String uid) => SessionUserIdentity(
    uid: uid,
    email: '$uid@example.com',
    displayName: uid,
  );

  testWidgets(
    'Dashboard no crea Login ni elimina la ruta raíz si Firebase ya no tiene usuario',
    (tester) async {
      final current = identity('dashboard-user');
      final auth = StreamController<SessionUserIdentity?>();
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, _, _) async {},
        signOutAction: () async {},
      );
      await controller.requestPreparation();
      final routes = _RouteObserver();
      final perfil = PerfilService(
        dataSource: _PerfilDataSource(Future.value(_profileRow(current.uid))),
        isSessionCurrent: () => true,
      );
      addTearDown(() async {
        controller.dispose();
        await auth.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: DashboardPage(
            perfilService: perfil,
            sessionController: controller,
            betaNoticeService: const _HiddenBetaNotice(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(routes.pushes, 1);
      expect(routes.removals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AuthGate conserva el flujo ready, unauthenticated y nuevo ready',
    (tester) async {
      SessionUserIdentity? current = identity('first-user');
      final auth = StreamController<SessionUserIdentity?>();
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, _, _) async {},
        signOutAction: () async {},
      );
      await controller.requestPreparation();
      final routes = _RouteObserver();
      addTearDown(() async {
        controller.dispose();
        await auth.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: AuthGate(
            sessionController: controller,
            loginBuilder: (_) => const Scaffold(body: Text('LOGIN-TEST')),
            readyBuilder: (_) => MainNavigation(
              sectionBuilder: (context, section, payload) => DashboardPage(
                sessionController: controller,
                betaNoticeService: const _HiddenBetaNotice(),
                initialLoadOverride: () async {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.byType(MainNavigation), findsOneWidget);
      expect(find.byType(DashboardPage), findsOneWidget);

      current = null;
      auth.add(null);
      await tester.pump();

      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.text('LOGIN-TEST'), findsOneWidget);
      expect(find.byType(MainNavigation), findsNothing);
      expect(routes.pushes, 1);
      expect(routes.removals, 0);

      await controller.authenticate<void>(
        operation: () async {
          current = identity('second-user');
          auth.add(current);
        },
      );
      await tester.pump();

      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.text('LOGIN-TEST'), findsNothing);
      expect(find.byType(MainNavigation), findsOneWidget);
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(routes.pushes, 1);
      expect(routes.removals, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'perfil que termina después del logout no navega ni usa un Dashboard desmontado',
    (tester) async {
      SessionUserIdentity? current = identity('slow-profile-user');
      final auth = StreamController<SessionUserIdentity?>();
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, _, _) async {},
        signOutAction: () async {},
      );
      await controller.requestPreparation();
      final pendingProfile = Completer<Map<String, dynamic>?>();
      final dataSource = _PerfilDataSource(pendingProfile.future);
      final perfil = PerfilService(
        dataSource: dataSource,
        isSessionCurrent: () => current?.uid == 'slow-profile-user',
      );
      final routes = _RouteObserver();
      addTearDown(() async {
        controller.dispose();
        await auth.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [routes],
          home: AuthGate(
            sessionController: controller,
            loginBuilder: (_) => const Scaffold(body: Text('LOGIN-TEST')),
            readyBuilder: (_) => MainNavigation(
              sectionBuilder: (context, section, payload) => DashboardPage(
                perfilService: perfil,
                sessionController: controller,
                betaNoticeService: const _HiddenBetaNotice(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(dataSource.reads, 1);
      expect(find.byType(DashboardPage), findsOneWidget);

      current = null;
      auth.add(null);
      await tester.pump();
      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.text('LOGIN-TEST'), findsOneWidget);
      expect(find.byType(DashboardPage), findsNothing);

      pendingProfile.complete(_profileRow('slow-profile-user'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(AuthGate), findsOneWidget);
      expect(find.text('LOGIN-TEST'), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(routes.pushes, 1);
      expect(routes.removals, 0);
      expect(tester.takeException(), isNull);
    },
  );
}

Map<String, dynamic> _profileRow(String uid) => {
  'uid': uid,
  'nombre': 'Estudiante',
  'correo_principal': '$uid@example.com',
  'correo_institucional': '',
  'nivel_educativo': null,
  'nombre_establecimiento': '',
  'tipo_establecimiento': '',
  'curso_actual': '',
  'carrera': '',
  'semestre_actual': null,
  'anio_ingreso': null,
  'sede': '',
  'jornada': '',
  'estado_academico': '',
  'idioma': 'es',
  'perfil_completo': false,
};

class _PerfilDataSource implements PerfilDataSource {
  _PerfilDataSource(this.result);

  final Future<Map<String, dynamic>?> result;
  int reads = 0;

  @override
  Future<void> actualizar(String uid, Map<String, dynamic> values) async {}

  @override
  Future<void> insertarSiFalta(Map<String, dynamic> values) async {}

  @override
  Future<Map<String, dynamic>?> obtener(String uid) {
    reads++;
    return result;
  }
}

class _HiddenBetaNotice implements BetaNoticeCoordinator {
  const _HiddenBetaNotice();

  @override
  Future<bool> markShown(
    BetaNoticeReservation reservation, {
    required bool Function() isValid,
  }) async => false;

  @override
  void release(BetaNoticeReservation reservation) {}

  @override
  Future<BetaNoticeReservation?> reserveIfShouldShow(
    String uid,
    BetaNoticeKind kind,
  ) async => null;
}

class _RouteObserver extends NavigatorObserver {
  int pushes = 0;
  int removals = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removals++;
  }
}
