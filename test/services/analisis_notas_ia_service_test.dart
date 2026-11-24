import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/evaluacion.dart';
import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/services/analisis_notas_ia_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = AnalisisNotasIaService();
  const configuracion = ConfiguracionNotas.predeterminada;
  final fecha = DateTime(2026, 10, 2);
  const matematica = Asignatura(
    id: 'mat',
    nombre: 'Matemática I',
    sigla: 'MAT101',
    estado: EstadoAsignatura.enCurso,
    origen: OrigenAsignatura.manual,
  );
  const fisica = Asignatura(
    id: 'fis',
    nombre: 'Física',
    sigla: 'FIS101',
    estado: EstadoAsignatura.enCurso,
    origen: OrigenAsignatura.manual,
  );
  final evaluaciones = [
    Evaluacion(
      id: 'e1',
      titulo: 'Prueba Álgebra',
      asignaturaId: 'mat',
      tipo: TipoEvaluacion.prueba,
      fecha: fecha,
      ponderacion: 50,
      creadaEn: fecha,
      actualizadaEn: fecha,
    ),
    Evaluacion(
      id: 'e2',
      titulo: 'Examen final',
      asignaturaId: 'mat',
      tipo: TipoEvaluacion.examen,
      fecha: fecha,
      ponderacion: 50,
      creadaEn: fecha,
      actualizadaEn: fecha,
    ),
    Evaluacion(
      id: 'e3',
      titulo: 'Examen final',
      asignaturaId: 'fis',
      tipo: TipoEvaluacion.examen,
      fecha: fecha,
      ponderacion: 100,
      creadaEn: fecha,
      actualizadaEn: fecha,
    ),
  ];

  test('filtra por sigla y resuelve un escenario sin persistirlo', () {
    final resultado = service.resolver(
      argumentos: {
        'asignatura': 'mat101',
        'escenarios': [
          {'evaluacion': 'examen final', 'nota': 5.5},
        ],
      },
      asignaturas: const [matematica, fisica],
      evaluaciones: evaluaciones,
      calificaciones: const {},
      configuracion: configuracion,
    );

    expect(resultado.asignaturas, [matematica]);
    expect(resultado.notasHipoteticas, {'e2': 5.5});
    expect(resultado.advertencias, isEmpty);
  });

  test('no permite que un escenario reemplace una nota real', () {
    final resultado = service.resolver(
      argumentos: {
        'asignatura': 'Matematica I',
        'escenarios': [
          {'evaluacion': 'Prueba Algebra', 'nota': 7},
        ],
      },
      asignaturas: const [matematica, fisica],
      evaluaciones: evaluaciones,
      calificaciones: const {
        'e1': CalificacionEvaluacion(evaluacionId: 'e1', nota: 4.8),
      },
      configuracion: configuracion,
    );

    expect(resultado.notasHipoteticas, isEmpty);
    expect(resultado.advertencias.single['codigo'], 'evaluacion_ya_calificada');
  });

  test('informa ambigüedad si falta asignatura y el título se repite', () {
    final resultado = service.resolver(
      argumentos: {
        'escenarios': [
          {'evaluacion': 'Examen final', 'nota': 5},
        ],
      },
      asignaturas: const [matematica, fisica],
      evaluaciones: evaluaciones,
      calificaciones: const {},
      configuracion: configuracion,
    );

    expect(resultado.notasHipoteticas, isEmpty);
    expect(resultado.advertencias.single['codigo'], 'evaluacion_ambigua');
  });

  test('rechaza notas hipotéticas fuera de la escala configurada', () {
    final resultado = service.resolver(
      argumentos: {
        'asignatura': 'Física',
        'escenarios': [
          {'evaluacion': 'Examen final', 'nota': 7.1},
        ],
      },
      asignaturas: const [matematica, fisica],
      evaluaciones: evaluaciones,
      calificaciones: const {},
      configuracion: configuracion,
    );

    expect(resultado.notasHipoteticas, isEmpty);
    expect(resultado.advertencias.single['codigo'], 'escenario_invalido');
  });
}
