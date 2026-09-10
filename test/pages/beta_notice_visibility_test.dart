import 'dart:async';

import 'package:eduflow_ai/core/auth/auth_gate.dart';
import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/core/navigation/main_navigation.dart';
import 'package:eduflow_ai/pages/ai/ai_chat_page.dart';
import 'package:eduflow_ai/pages/dashboard/dashboard_page.dart';
import 'package:eduflow_ai/services/beta_notice_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FirebaseAuthTestHost().initialize);

  ({SessionController controller, StreamController<SessionUserIdentity?> auth})
  readyController() {
    const current = SessionUserIdentity(
      uid: 'beta-user',
      email: 'beta@example.com',
      displayName: 'Beta',
    );
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );
    return (controller: controller, auth: auth);
  }

  testWidgets('Dashboard visible y listo muestra la bienvenida Beta', (
    tester,
  ) async {
    final session = readyController();
    final beta = _FakeBetaNotice();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          sessionController: session.controller,
          betaNoticeService: beta,
          initialLoadOverride: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(beta.reservationCalls, 1);
    expect(find.text('Bienvenido a EducFlow AI'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pump();
    expect(beta.marked, [('beta-user', BetaNoticeKind.welcome)]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Login y preparing nunca evalúan Beta antes de ready', (
    tester,
  ) async {
    SessionUserIdentity? current;
    final auth = StreamController<SessionUserIdentity?>();
    final preparation = Completer<void>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) => preparation.future,
      signOutAction: () async {},
    );
    final beta = _FakeBetaNotice();
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          sessionController: controller,
          loginBuilder: (_) => const Scaffold(body: Text('LOGIN-TEST')),
          readyBuilder: (_) => DashboardPage(
            sessionController: controller,
            betaNoticeService: beta,
            initialLoadOverride: () async {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('LOGIN-TEST'), findsOneWidget);
    expect(beta.reservationCalls, 0);

    current = const SessionUserIdentity(
      uid: 'new-user',
      email: 'new@example.com',
      displayName: 'New',
    );
    auth.add(current);
    await tester.pump();
    await tester.pump();
    expect(find.text('Preparando tu espacio…'), findsOneWidget);
    expect(beta.reservationCalls, 0);

    preparation.complete();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(beta.reservationCalls, 1);
    expect(find.text('Bienvenido a EducFlow AI'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pump();
  });

  testWidgets('excepción del diálogo libera la reserva y permite reintentar', (
    tester,
  ) async {
    final session = readyController();
    final beta = _FakeBetaNotice();
    Future<void> failingPresenter(
      BuildContext context, {
      required bool spanish,
      required BetaNoticeKind kind,
      GlobalKey? dialogKey,
      VoidCallback? onInvalidated,
    }) async {
      throw StateError('diálogo');
    }

    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    Widget dashboard() => MaterialApp(
      home: DashboardPage(
        sessionController: session.controller,
        betaNoticeService: beta,
        betaDialogPresenter: failingPresenter,
        initialLoadOverride: () async {},
      ),
    );

    await tester.pumpWidget(dashboard());
    await tester.pump();
    await tester.pump();
    expect(beta.reservationCalls, 1);
    expect(beta.released, [('beta-user', BetaNoticeKind.welcome)]);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(dashboard());
    await tester.pump();
    await tester.pump();
    expect(beta.reservationCalls, 2);
    expect(beta.released, [
      ('beta-user', BetaNoticeKind.welcome),
      ('beta-user', BetaNoticeKind.welcome),
    ]);
    expect(tester.takeException(), isNull);
  });

  for (final coveringRoute in ['Perfil', 'Registro']) {
    testWidgets('Dashboard detrás de $coveringRoute no muestra Beta', (
      tester,
    ) async {
      final session = readyController();
      final beta = _FakeBetaNotice();
      final load = Completer<void>();
      addTearDown(() async {
        session.controller.dispose();
        await session.auth.close();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Stack(
              children: [
                DashboardPage(
                  sessionController: session.controller,
                  betaNoticeService: beta,
                  initialLoadOverride: () => load.future,
                ),
                Align(
                  alignment: Alignment.topLeft,
                  child: ElevatedButton(
                    key: const Key('cover-dashboard'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(body: Text(coveringRoute)),
                      ),
                    ),
                    child: const Text('CUBRIR'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('cover-dashboard')));
      await tester.pumpAndSettle();
      load.complete();
      await tester.pump();
      await tester.pump();

      expect(beta.reservationCalls, 0);
      expect(find.text('Bienvenido a EducFlow AI'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('IA cargada pero no visible no consulta ni muestra Beta', (
    tester,
  ) async {
    final session = readyController();
    final beta = _FakeBetaNotice();
    final load = Completer<void>();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Stack(
            children: [
              AiChatPage(
                sessionController: session.controller,
                betaNoticeService: beta,
                initialConversationLoadOverride: () => load.future,
              ),
              Align(
                alignment: Alignment.topLeft,
                child: ElevatedButton(
                  key: const Key('cover-ai'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('Perfil')),
                    ),
                  ),
                  child: const Text('CUBRIR'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('cover-ai')));
    await tester.pumpAndSettle();
    load.complete();
    await tester.pump();
    await tester.pump();

    expect(beta.reservationCalls, 0);
    expect(find.text('EducFlow AI está en beta'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('IA visible y cargada muestra su aviso Beta', (tester) async {
    final session = readyController();
    final beta = _FakeBetaNotice();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AiChatPage(
          sessionController: session.controller,
          betaNoticeService: beta,
          initialConversationLoadOverride: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(beta.reservationCalls, 1);
    expect(find.text('EducFlow AI está en beta'), findsOneWidget);
    await tester.tap(find.text('Entendido'));
    await tester.pump();
    expect(beta.marked, [('beta-user', BetaNoticeKind.ai)]);
  });

  testWidgets('IA deja su sección durante la carga y no muestra Beta', (
    tester,
  ) async {
    final session = readyController();
    final beta = _FakeBetaNotice();
    final load = Completer<void>();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigation(
          sectionBuilder: (context, section, payload) {
            if (section == SeccionPrincipal.ia) {
              return AiChatPage(
                sessionController: session.controller,
                betaNoticeService: beta,
                initialConversationLoadOverride: () => load.future,
              );
            }
            return Scaffold(body: Text('SECCION-${section.name}'));
          },
        ),
      ),
    );
    MainNavigation.goTo(
      tester.element(find.text('SECCION-inicio')),
      SeccionPrincipal.ia,
    );
    await tester.pump();
    expect(find.byType(AiChatPage), findsOneWidget);

    MainNavigation.goTo(
      tester.element(find.byType(AiChatPage)),
      SeccionPrincipal.calendario,
    );
    await tester.pump();
    load.complete();
    await tester.pump();
    await tester.pump();

    expect(find.text('SECCION-calendario'), findsOneWidget);
    expect(beta.reservationCalls, 0);
    expect(find.text('EducFlow AI está en beta'), findsNothing);
  });

  testWidgets('Beta abierta se cierra al cambiar de sección y no se marca', (
    tester,
  ) async {
    final session = readyController();
    final beta = _FakeBetaNotice();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: MainNavigation(
          sectionBuilder: (context, section, payload) {
            if (section == SeccionPrincipal.inicio) {
              return DashboardPage(
                sessionController: session.controller,
                betaNoticeService: beta,
                initialLoadOverride: () async {},
              );
            }
            return Scaffold(body: Text('SECCION-${section.name}'));
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Bienvenido a EducFlow AI'), findsOneWidget);

    MainNavigation.goTo(
      tester.element(find.byType(DashboardPage)),
      SeccionPrincipal.horario,
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('SECCION-horario'), findsOneWidget);
    expect(find.text('Bienvenido a EducFlow AI'), findsNothing);
    expect(beta.marked, isEmpty);
    expect(beta.released, [('beta-user', BetaNoticeKind.welcome)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Beta abierta se invalida si otra ruta la cubre', (tester) async {
    final session = readyController();
    final beta = _FakeBetaNotice();
    addTearDown(() async {
      session.controller.dispose();
      await session.auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          sessionController: session.controller,
          betaNoticeService: beta,
          initialLoadOverride: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Bienvenido a EducFlow AI'), findsOneWidget);

    Navigator.of(tester.element(find.byType(DashboardPage))).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('PERFIL-TEST')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PERFIL-TEST'), findsOneWidget);
    expect(find.text('Bienvenido a EducFlow AI'), findsNothing);
    Navigator.of(tester.element(find.text('PERFIL-TEST'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Bienvenido a EducFlow AI'), findsNothing);
    expect(beta.marked, isEmpty);
    expect(beta.released, [('beta-user', BetaNoticeKind.welcome)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('markShown pendiente no marca tras cambiar de sesión', (
    tester,
  ) async {
    SessionUserIdentity current = const SessionUserIdentity(
      uid: 'beta-user',
      email: 'beta@example.com',
      displayName: 'Beta',
    );
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );
    final beta = _FakeBetaNotice()..pauseMarking();
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          sessionController: controller,
          betaNoticeService: beta,
          betaDialogPresenter: (
            context, {
            required spanish,
            required kind,
            dialogKey,
            onInvalidated,
          }) async {},
          initialLoadOverride: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await beta.markStarted.future;

    current = const SessionUserIdentity(
      uid: 'other-user',
      email: 'other@example.com',
      displayName: 'Other',
    );
    auth.add(current);
    await tester.pump();
    beta.finishMarking();
    await tester.pump();
    await tester.pump();

    expect(beta.marked, isEmpty);
    expect(beta.released, [('beta-user', BetaNoticeKind.welcome)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambio de UID cierra el diálogo y no marca a otra cuenta', (
    tester,
  ) async {
    SessionUserIdentity current = const SessionUserIdentity(
      uid: 'beta-user',
      email: 'beta@example.com',
      displayName: 'Beta',
    );
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );
    final beta = _FakeBetaNotice();
    addTearDown(() async {
      controller.dispose();
      await auth.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(
          sessionController: controller,
          betaNoticeService: beta,
          initialLoadOverride: () async {},
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Bienvenido a EducFlow AI'), findsOneWidget);

    current = const SessionUserIdentity(
      uid: 'other-user',
      email: 'other@example.com',
      displayName: 'Other',
    );
    auth.add(current);
    await tester.pump();
    await tester.pump();

    expect(find.text('Bienvenido a EducFlow AI'), findsNothing);
    expect(beta.marked, isEmpty);
    expect(beta.released, [('beta-user', BetaNoticeKind.welcome)]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _FakeBetaNotice implements BetaNoticeCoordinator {
  int reservationCalls = 0;
  final marked = <(String, BetaNoticeKind)>[];
  final released = <(String, BetaNoticeKind)>[];
  Completer<void> markStarted = Completer<void>();
  Completer<void>? _markBarrier;

  void pauseMarking() {
    markStarted = Completer<void>();
    _markBarrier = Completer<void>();
  }

  void finishMarking() {
    _markBarrier?.complete();
    _markBarrier = null;
  }

  @override
  Future<BetaNoticeReservation?> reserveIfShouldShow(
    String uid,
    BetaNoticeKind kind,
  ) async {
    reservationCalls++;
    return BetaNoticeReservation.forTesting(uid, kind);
  }

  @override
  Future<bool> markShown(
    BetaNoticeReservation reservation, {
    required bool Function() isValid,
  }) async {
    if (!markStarted.isCompleted) markStarted.complete();
    final barrier = _markBarrier;
    if (barrier != null) await barrier.future;
    if (!isValid()) return false;
    marked.add((reservation.uid, reservation.kind));
    return true;
  }

  @override
  void release(BetaNoticeReservation reservation) {
    released.add((reservation.uid, reservation.kind));
  }
}
