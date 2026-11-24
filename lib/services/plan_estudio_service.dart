import 'dart:async';

import '../models/plan_estudio.dart';
import '../models/tarea.dart';
import 'tareas_service.dart';

abstract interface class PlanEstudioPersistence {
  Future<ResultadoGuardadoPlanEstudio> guardar(PlanEstudioPropuesto plan);
}

abstract interface class PlanEstudioStatusReader {
  Future<Set<String>> obtenerIdsPlanesGuardados();
}

class PlanEstudioPersistenceException implements Exception {
  const PlanEstudioPersistenceException({
    required this.sesionesGuardadas,
    required this.cause,
  });

  final int sesionesGuardadas;
  final Object cause;

  @override
  String toString() =>
      'No fue posible completar el plan de estudio '
      '($sesionesGuardadas sesiones confirmadas).';
}

class PlanEstudioService
    implements PlanEstudioPersistence, PlanEstudioStatusReader {
  PlanEstudioService({TareasService? tareasService})
    : _tareasService = tareasService ?? TareasService.instance;

  static final PlanEstudioService instance = PlanEstudioService();

  final TareasService _tareasService;
  final Map<String, Future<ResultadoGuardadoPlanEstudio>> _operaciones = {};

  @override
  Future<Set<String>> obtenerIdsPlanesGuardados() async {
    final tareas = await _tareasService.obtenerTodas();
    return tareas
        .map((tarea) => tarea.descripcion ?? '')
        .expand(_extraerIdentificadoresPlan)
        .toSet();
  }

  @override
  Future<ResultadoGuardadoPlanEstudio> guardar(PlanEstudioPropuesto plan) {
    final existente = _operaciones[plan.id];
    if (existente != null) return existente;

    final operacion = _guardarInterno(plan);
    _operaciones[plan.id] = operacion;
    return operacion.whenComplete(() {
      if (identical(_operaciones[plan.id], operacion)) {
        _operaciones.remove(plan.id);
      }
    });
  }

  Future<ResultadoGuardadoPlanEstudio> _guardarInterno(
    PlanEstudioPropuesto plan,
  ) async {
    if (plan.id.trim().isEmpty || plan.sesiones.isEmpty) {
      throw ArgumentError('El plan debe contener sesiones identificables.');
    }

    final tareas = await _tareasService.obtenerTodas();
    final marcadoresExistentes = tareas
        .map((tarea) => tarea.descripcion ?? '')
        .expand(_extraerMarcadores)
        .toSet();
    var creadas = 0;
    var yaExistentes = 0;

    try {
      for (final sesion in plan.sesiones) {
        final marcador = marcadorSesion(plan.id, sesion.id);
        if (marcadoresExistentes.contains(marcador)) {
          yaExistentes++;
          continue;
        }

        await _tareasService.crear(
          titulo: 'Estudio: ${sesion.titulo}',
          descripcion: _descripcion(plan, sesion, marcador),
          asignaturaId: plan.asignaturaId,
          prioridad: PrioridadTarea.media,
          fechaEntrega: sesion.fecha,
          horaEntrega: sesion.horaInicio,
        );
        marcadoresExistentes.add(marcador);
        creadas++;
      }
    } catch (error) {
      throw PlanEstudioPersistenceException(
        sesionesGuardadas: creadas + yaExistentes,
        cause: error,
      );
    }

    return ResultadoGuardadoPlanEstudio(
      creadas: creadas,
      yaExistentes: yaExistentes,
    );
  }

  static String marcadorSesion(String planId, String sesionId) =>
      '[EDUFLOW_PLAN_ESTUDIO:$planId:$sesionId]';

  static Iterable<String> _extraerMarcadores(String descripcion) sync* {
    final matches = RegExp(r'\[EDUFLOW_PLAN_ESTUDIO:[^\]\r\n]+\]')
        .allMatches(descripcion);
    for (final match in matches) {
      yield match.group(0)!;
    }
  }

  static Iterable<String> _extraerIdentificadoresPlan(
    String descripcion,
  ) sync* {
    final matches = RegExp(r'\[EDUFLOW_PLAN_ESTUDIO:([^:\]\r\n]+):[^\]\r\n]+\]')
        .allMatches(descripcion);
    for (final match in matches) {
      yield match.group(1)!;
    }
  }

  static String _descripcion(
    PlanEstudioPropuesto plan,
    SesionPlanEstudio sesion,
    String marcador,
  ) =>
      'Plan de estudio: ${plan.titulo}\n'
      'Objetivo: ${plan.objetivo}\n'
      'Actividad: ${sesion.actividad}\n'
      'Duración: ${sesion.duracionMinutos} minutos\n'
      '$marcador';
}
