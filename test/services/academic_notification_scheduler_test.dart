import 'dart:async';

import 'package:eduflow_ai/core/auth/session_controller.dart';
import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/services/academic_notification_scheduler.dart';
import 'package:eduflow_ai/services/user_preferences_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SessionUserIdentity identity(String uid) => SessionUserIdentity(
    uid: uid,
    email: '$uid@example.com',
    displayName: uid,
  );

  Future<void> flushSessionChanges() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  Tarea futureTask(String uid) {
    final now = DateTime.now();
    return Tarea(
      id: 'task-$uid',
      titulo: 'Tarea $uid',
      prioridad: PrioridadTarea.media,
      estado: EstadoTarea.pendiente,
      fechaEntrega: now.add(const Duration(days: 3)),
      creadaEn: now,
      actualizadaEn: now,
    );
  }

  test(
    'A logout B serializa la limpieza lenta antes de programar la sesión nueva',
    () async {
      SessionUserIdentity? current = identity('a');
      final auth = StreamController<SessionUserIdentity?>();
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, _, _) async {},
        signOutAction: () async {},
      );
      await controller.requestPreparation();
      final notifications = _FakeNotifications()
        ..pending[100] = 'academic|task|old-a'
        ..pauseNextCancellation();
      final scheduler = _scheduler(
        controller: controller,
        notifications: notifications,
        loadTasks: () async => [futureTask(current!.uid)],
      );
      scheduler.start();
      addTearDown(() async {
        await scheduler.dispose();
        controller.dispose();
        await auth.close();
      });

      current = null;
      auth.add(null);
      await notifications.cancellationStarted.future;

      current = identity('b');
      await controller.authenticate<void>(
        operation: () async {
          auth.add(current);
        },
      );
      final syncB = scheduler.syncNow();
      await flushSessionChanges();

      expect(controller.status, SessionStatus.ready);
      expect(controller.activeUid, 'b');
      expect(notifications.scheduled, isEmpty);

      notifications.finishCancellation();
      await syncB;

      expect(notifications.pending.values, contains('academic|task|task-b'));
      expect(
        notifications.pending.values,
        isNot(contains('academic|task|old-a')),
      );
    },
  );

  test('misma UID en una generación nueva espera la limpieza de la generación anterior', () async {
    SessionUserIdentity? current = identity('same-user');
    final auth = StreamController<SessionUserIdentity?>();
    final controller = SessionController(
      currentUserProvider: () => current,
      authChanges: auth.stream,
      sessionPreparation: (_, _, _) async {},
      signOutAction: () async {},
    );
    await controller.requestPreparation();
    final firstTicket = controller.captureTicket()!;
    final notifications = _FakeNotifications()
      ..pending[200] = 'academic|task|old-generation'
      ..pauseNextCancellation();
    final scheduler = _scheduler(
      controller: controller,
      notifications: notifications,
      loadTasks: () async => [futureTask('same-user')],
    );
    scheduler.start();
    addTearDown(() async {
      await scheduler.dispose();
      controller.dispose();
      await auth.close();
    });

    current = null;
    auth.add(null);
    await notifications.cancellationStarted.future;

    current = identity('same-user');
    await controller.authenticate<void>(
      operation: () async {
        auth.add(current);
      },
    );
    final secondTicket = controller.captureTicket()!;
    final newGenerationSync = scheduler.syncNow();
    await flushSessionChanges();

    expect(secondTicket.uid, firstTicket.uid);
    expect(secondTicket.generation, isNot(firstTicket.generation));
    expect(notifications.scheduled, isEmpty);

    notifications.finishCancellation();
    await newGenerationSync;

    expect(
      notifications.pending.values,
      contains('academic|task|task-same-user'),
    );
    expect(
      notifications.pending.values,
      isNot(contains('academic|task|old-generation')),
    );
  });

  test(
    'syncNow antiguo no produce efectos después de invalidar su ticket',
    () async {
      SessionUserIdentity? current = identity('a');
      final auth = StreamController<SessionUserIdentity?>();
      final preferencesPending = Completer<void>();
      final preferencesStarted = Completer<void>();
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, _, _) async {},
        signOutAction: () async {},
      );
      await controller.requestPreparation();
      final notifications = _FakeNotifications();
      final scheduler = _scheduler(
        controller: controller,
        notifications: notifications,
        loadTasks: () async => [futureTask('a')],
        beforePreferences: () async {
          if (!preferencesStarted.isCompleted) {
            preferencesStarted.complete();
            await preferencesPending.future;
          }
        },
      );
      scheduler.start();
      addTearDown(() async {
        await scheduler.dispose();
        controller.dispose();
        await auth.close();
      });

      final oldSync = scheduler.syncNow();
      await preferencesStarted.future;

      current = identity('b');
      auth.add(current);
      await flushSessionChanges();
      preferencesPending.complete();
      await oldSync;
      await scheduler.waitForIdle();

      expect(controller.activeUid, 'b');
      expect(notifications.scheduled, isEmpty);
      expect(notifications.cancelled, isEmpty);
    },
  );

  test(
    'logout normal limpia las notificaciones académicas anteriores',
    () async {
      SessionUserIdentity? current = identity('a');
      final auth = StreamController<SessionUserIdentity?>();
      final controller = SessionController(
        currentUserProvider: () => current,
        authChanges: auth.stream,
        sessionPreparation: (_, _, _) async {},
        signOutAction: () async {},
      );
      await controller.requestPreparation();
      final notifications = _FakeNotifications()
        ..pending.addAll({
          1: 'academic|task|a',
          2: 'general',
          3: 'academic|evaluation|a',
        });
      final scheduler = _scheduler(
        controller: controller,
        notifications: notifications,
      );
      scheduler.start();
      addTearDown(() async {
        await scheduler.dispose();
        controller.dispose();
        await auth.close();
      });

      current = null;
      auth.add(null);
      await flushSessionChanges();
      await scheduler.waitForIdle();

      expect(notifications.cancelled, [1, 3]);
      expect(notifications.pending, {2: 'general'});
    },
  );
}

AcademicNotificationScheduler _scheduler({
  required SessionController controller,
  required _FakeNotifications notifications,
  Future<List<Tarea>> Function()? loadTasks,
  Future<void> Function()? beforePreferences,
}) {
  return AcademicNotificationScheduler.forTesting(
    sessionController: controller,
    loadPendingNotifications: notifications.loadPending,
    cancelNotification: notifications.cancel,
    scheduleNotification: notifications.schedule,
    loadPreferences: () async {
      await beforePreferences?.call();
      return UserPreferences.defaults;
    },
    loadTasks: loadTasks,
  );
}

class _FakeNotifications {
  final Map<int, String> pending = {};
  final List<int> cancelled = [];
  final List<AcademicNotificationRequest> scheduled = [];
  Completer<void> cancellationStarted = Completer<void>();
  Completer<void>? _cancellationBarrier;

  void pauseNextCancellation() {
    cancellationStarted = Completer<void>();
    _cancellationBarrier = Completer<void>();
  }

  void finishCancellation() {
    _cancellationBarrier?.complete();
    _cancellationBarrier = null;
  }

  Future<List<AcademicPendingNotification>> loadPending() async {
    return pending.entries
        .map(
          (entry) =>
              AcademicPendingNotification(id: entry.key, payload: entry.value),
        )
        .toList();
  }

  Future<void> cancel(int id) async {
    if (!cancellationStarted.isCompleted) {
      cancellationStarted.complete();
    }
    final barrier = _cancellationBarrier;
    if (barrier != null) {
      await barrier.future;
    }
    cancelled.add(id);
    pending.remove(id);
  }

  Future<void> schedule(AcademicNotificationRequest request) async {
    scheduled.add(request);
    pending[request.id] = request.payload;
  }
}
