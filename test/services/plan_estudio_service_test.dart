import 'dart:async';

import 'package:eduflow_ai/models/plan_estudio.dart';
import 'package:eduflow_ai/models/tarea.dart';
import 'package:eduflow_ai/services/plan_estudio_service.dart';
import 'package:eduflow_ai/services/tareas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'confirma sesiones como tareas y evita duplicarlas al reintentar',
    () async {
      var uid = 'user-1';
      final source = _MemoryTasks();
      final tasks = TareasService(
        dataSource: source,
        uidProvider: () => uid,
        limpiarEstadoNotificacion: (_) async {},
      );
      final service = PlanEstudioService(tareasService: tasks);
      final plan = _plan();

      final first = await service.guardar(plan);
      final retry = await service.guardar(plan);

      expect(first.creadas, 2);
      expect(first.yaExistentes, 0);
      expect(retry.creadas, 0);
      expect(retry.yaExistentes, 2);
      expect(source.forUser('user-1'), hasLength(2));
      expect(
        source.forUser('user-1').first.fechaEntrega,
        DateTime(2026, 11, 24),
      );
      expect(source.forUser('user-1').first.horaEntrega, '16:00');
      expect(source.forUser('user-1').first.asignaturaId, 'bpm-1');
      expect(source.forUser('user-1').first.titulo, 'Estudio: Teoría');
      expect(
        source.forUser('user-1').first.descripcion,
        contains('[EDUFLOW_PLAN_ESTUDIO:plan-1:session-1]'),
      );
      expect(await service.obtenerIdsPlanesGuardados(), {'plan-1'});

      uid = 'user-2';
      final otherAccount = await service.guardar(plan);
      expect(otherAccount.creadas, 2);
      expect(source.forUser('user-2'), hasLength(2));
      expect(source.forUser('user-1'), hasLength(2));
      expect(await service.obtenerIdsPlanesGuardados(), {'plan-1'});
    },
  );

  test(
    'un fallo parcial se puede reintentar sin duplicar lo confirmado',
    () async {
      final source = _MemoryTasks()..failCreationNumber = 2;
      final tasks = TareasService(
        dataSource: source,
        uidProvider: () => 'user-1',
        limpiarEstadoNotificacion: (_) async {},
      );
      final service = PlanEstudioService(tareasService: tasks);

      await expectLater(
        service.guardar(_plan()),
        throwsA(isA<PlanEstudioPersistenceException>()),
      );
      source.failCreationNumber = null;
      final retry = await service.guardar(_plan());

      expect(retry.creadas, 1);
      expect(retry.yaExistentes, 1);
      expect(source.forUser('user-1'), hasLength(2));
    },
  );

  test('dos confirmaciones simultáneas comparten una sola escritura', () async {
    final source = _MemoryTasks();
    final tasks = TareasService(
      dataSource: source,
      uidProvider: () => 'user-1',
      limpiarEstadoNotificacion: (_) async {},
    );
    final service = PlanEstudioService(tareasService: tasks);

    final results = await Future.wait([
      service.guardar(_plan()),
      service.guardar(_plan()),
    ]);

    expect(results[0].creadas, 2);
    expect(results[1].creadas, 2);
    expect(source.forUser('user-1'), hasLength(2));
  });
}

PlanEstudioPropuesto _plan() => PlanEstudioPropuesto(
  id: 'plan-1',
  titulo: 'Plan BPM',
  objetivo: 'Preparar evaluación',
  asignaturaId: 'bpm-1',
  asignaturaNombre: 'BPM',
  evaluacionId: 'evaluation-1',
  revision: 1,
  sesiones: [
    SesionPlanEstudio(
      id: 'session-1',
      titulo: 'Teoría',
      actividad: 'Repasar apuntes',
      fecha: DateTime(2026, 11, 24),
      horaInicio: '16:00',
      duracionMinutos: 45,
    ),
    SesionPlanEstudio(
      id: 'session-2',
      titulo: 'Práctica',
      actividad: 'Resolver ejercicios',
      fecha: DateTime(2026, 11, 25),
      horaInicio: '17:00',
      duracionMinutos: 45,
    ),
  ],
);

class _MemoryTasks implements TareasDataSource {
  final Map<String, List<Tarea>> _byUser = {};
  int creations = 0;
  int? failCreationNumber;

  List<Tarea> forUser(String uid) =>
      List.unmodifiable(_byUser[uid] ?? const []);

  @override
  Future<List<Tarea>> obtenerTodas(String uid) async => List.of(forUser(uid));

  @override
  Future<Tarea?> obtenerPorId(String uid, String id) async {
    for (final task in _byUser[uid] ?? const <Tarea>[]) {
      if (task.id == id) return task;
    }
    return null;
  }

  @override
  Future<Tarea> crear(String uid, Tarea tarea) async {
    creations++;
    if (failCreationNumber == creations) throw StateError('simulated failure');
    final saved = tarea.copyWith(id: 'task-$uid-$creations');
    _byUser.putIfAbsent(uid, () => []).add(saved);
    return saved;
  }

  @override
  Future<Tarea> actualizar(String uid, Tarea tarea) async => tarea;

  @override
  Future<void> eliminar(String uid, String id) async {
    _byUser[uid]?.removeWhere((item) => item.id == id);
  }

  @override
  Stream<void> observarCambios(String uid) => const Stream.empty();
}
