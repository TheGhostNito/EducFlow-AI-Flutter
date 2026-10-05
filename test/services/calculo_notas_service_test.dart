import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/services/calculo_notas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = CalculoNotasService();
  const config = ConfiguracionNotas.predeterminada;

  EntradaCalculoNota item(
    String id,
    double weight, {
    double? grade,
    double? hypothetical,
  }) {
    return EntradaCalculoNota(
      id: id,
      nombre: id,
      ponderacion: weight,
      notaReal: grade,
      notaHipotetica: hypothetical,
    );
  }

  test('calcula promedio ponderado normal y aporte final', () {
    final result = service.calcular(
      evaluaciones: [
        item('prueba', 40, grade: 5),
        item('examen', 60, grade: 6),
      ],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.promedioParcial, closeTo(5.6, 0.000001));
    expect(result.aporteAcumulado, closeTo(5.6, 0.000001));
    expect(result.resultadoFinalProyectado, closeTo(5.6, 0.000001));
    expect(result.pesoEvaluado, 100);
  });

  test('normaliza el promedio parcial cuando hay evaluaciones pendientes', () {
    final result = service.calcular(
      evaluaciones: [item('prueba', 40, grade: 5.5), item('examen', 60)],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.promedioParcial, closeTo(5.5, 0.000001));
    expect(result.aporteAcumulado, closeTo(2.2, 0.000001));
    expect(result.pesoEvaluado, 40);
    expect(result.pesoPendiente, 60);
  });

  test('calcula nota necesaria cuando queda una evaluación', () {
    final result = service.calcular(
      evaluaciones: [item('prueba', 40, grade: 5), item('examen', 60)],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.notaNecesariaUnica, closeTo(10 / 3, 0.000001));
    expect(result.promedioNecesarioRestante, closeTo(10 / 3, 0.000001));
  });

  test('con varias pendientes informa promedio requerido y no nota única', () {
    final result = service.calcular(
      evaluaciones: [
        item('prueba', 40, grade: 5),
        item('control', 20),
        item('examen', 40),
      ],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.promedioNecesarioRestante, closeTo(10 / 3, 0.000001));
    expect(result.notaNecesariaUnica, isNull);
    expect(result.evaluacionesPendientes, 2);
  });

  test('detecta un objetivo matemáticamente imposible', () {
    final result = service.calcular(
      evaluaciones: [item('trabajos', 80, grade: 1), item('examen', 20)],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.maximoFinalPosible, closeTo(2.2, 0.000001));
    expect(result.estadoObjetivo, EstadoObjetivoNota.imposible);
    expect(result.alerta, AlertaAcademicaNota.objetivoImposible);
  });

  test('detecta un objetivo ya asegurado', () {
    final result = service.calcular(
      evaluaciones: [item('trabajos', 80, grade: 7), item('examen', 20)],
      configuracion: config,
      objetivo: 5,
    );

    expect(result.minimoFinalPosible, closeTo(5.8, 0.000001));
    expect(result.estadoObjetivo, EstadoObjetivoNota.asegurado);
    expect(result.alerta, AlertaAcademicaNota.objetivoAsegurado);
  });

  test('marca como exigente el 75 por ciento superior de la escala', () {
    final result = service.calcular(
      evaluaciones: [item('prueba', 50, grade: 4), item('examen', 50)],
      configuracion: config,
      objetivo: 4.75,
    );

    expect(result.promedioNecesarioRestante, closeTo(5.5, 0.000001));
    expect(result.estadoObjetivo, EstadoObjetivoNota.exigente);
    expect(result.alerta, AlertaAcademicaNota.objetivoExigente);
  });

  test('el umbral exigente se adapta a la escala configurada', () {
    const custom = ConfiguracionNotas(
      notaMinima: 0,
      notaMaxima: 100,
      notaAprobacion: 60,
      decimales: 0,
      politicaRedondeo: PoliticaRedondeoNotas.masCercano,
    );
    final result = service.calcular(
      evaluaciones: [item('parcial', 50, grade: 50), item('final', 50)],
      configuracion: custom,
      objetivo: 62.5,
    );

    expect(result.promedioNecesarioRestante, closeTo(75, 0.000001));
    expect(result.estadoObjetivo, EstadoObjetivoNota.exigente);
  });

  test('un escenario hipotético no reemplaza la nota real', () {
    final result = service.calcular(
      evaluaciones: [
        item('prueba', 50, grade: 5),
        item('examen', 50, hypothetical: 7),
      ],
      configuracion: config,
      objetivo: 6,
    );

    expect(result.aporteHipotetico, closeTo(3.5, 0.000001));
    expect(result.resultadoFinalProyectado, closeTo(6, 0.000001));
    expect(result.promedioParcial, closeTo(6, 0.000001));
  });

  test('el escenario despeja una nota exacta tras fijar las demás', () {
    final result = service.calcular(
      evaluaciones: [
        item('prueba', 40, grade: 5),
        item('presentacion', 20, hypothetical: 6),
        item('examen', 40),
      ],
      configuracion: config,
      objetivo: 5,
    );

    expect(result.notaNecesariaUnica, closeTo(4.5, 0.000001));
    expect(result.promedioNecesarioRestante, closeTo(4.5, 0.000001));
  });

  test('marca ponderaciones incompletas sin ocultar porcentaje restante', () {
    final result = service.calcular(
      evaluaciones: [item('prueba', 30, grade: 5), item('examen', 50)],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.estadoPonderaciones, EstadoPonderacionesNotas.incompletas);
    expect(result.pesoConfigurado, 80);
    expect(result.pesoSinDistribuir, 20);
    expect(result.alerta, AlertaAcademicaNota.configuracionIncompleta);
  });

  test('rechaza ponderaciones que exceden 100 por ciento', () {
    final result = service.calcular(
      evaluaciones: [item('prueba', 60), item('examen', 50)],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.esValido, isFalse);
    expect(result.estadoPonderaciones, EstadoPonderacionesNotas.excedidas);
    expect(result.errores, contains('ponderaciones_exceden_100'));
  });

  test('respeta una escala configurable', () {
    const custom = ConfiguracionNotas(
      notaMinima: 0,
      notaMaxima: 100,
      notaAprobacion: 60,
      decimales: 0,
      politicaRedondeo: PoliticaRedondeoNotas.masCercano,
    );
    final result = service.calcular(
      evaluaciones: [item('parcial', 50, grade: 80), item('final', 50)],
      configuracion: custom,
      objetivo: 60,
    );

    expect(result.promedioNecesarioRestante, closeTo(40, 0.000001));
    expect(result.esValido, isTrue);
  });

  test('aplica redondeo al más cercano o truncado solo al presentar', () {
    const nearest = ConfiguracionNotas(
      notaMinima: 1,
      notaMaxima: 7,
      notaAprobacion: 4,
      decimales: 1,
      politicaRedondeo: PoliticaRedondeoNotas.masCercano,
    );
    const truncate = ConfiguracionNotas(
      notaMinima: 1,
      notaMaxima: 7,
      notaAprobacion: 4,
      decimales: 1,
      politicaRedondeo: PoliticaRedondeoNotas.truncar,
    );

    expect(service.redondear(5.55, nearest), 5.6);
    expect(service.redondear(5.59, truncate), 5.5);
  });

  test('rechaza notas bajo el mínimo y sobre el máximo', () {
    final result = service.calcular(
      evaluaciones: [
        item('baja', 50, grade: 0.9),
        item('alta', 50, grade: 7.1),
      ],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.esValido, isFalse);
    expect(
      result.errores.where((error) => error.startsWith('nota_fuera_de_escala')),
      hasLength(2),
    );
    expect(result.promedioParcial, isNull);
  });

  test('maneja ponderaciones cero y evita división por cero', () {
    final result = service.calcular(
      evaluaciones: [item('diagnostico', 0, grade: 7)],
      configuracion: config,
      objetivo: 4,
    );

    expect(result.promedioParcial, isNull);
    expect(result.aporteAcumulado, 0);
    expect(result.pesoEvaluado, 0);
  });

  group('estado académico final', () {
    test('directo al 100 % queda evaluado y aprobado sin proyección', () {
      final result = service.calcular(
        evaluaciones: [
          item('prueba', 50, grade: 6),
          item('trabajo', 50, grade: 5.6),
        ],
        configuracion: config,
        objetivo: 6,
      );

      expect(result.resultadoFinalProyectado, closeTo(5.8, 0.000001));
      expect(result.estadoAcademico, EstadoAcademicoNota.aprobado);
      expect(result.estaFinalizada, isTrue);
      expect(result.pesoPendiente, 0);
      expect(result.promedioNecesarioRestante, isNull);
      expect(result.notaNecesariaUnica, isNull);
      expect(result.estadoObjetivo, EstadoObjetivoNota.imposible);
    });

    test('objetivo inferior no cambia el estado académico aprobado', () {
      final result = service.calcular(
        evaluaciones: [item('final', 100, grade: 5.8)],
        configuracion: config,
        objetivo: 5,
      );

      expect(result.estadoAcademico, EstadoAcademicoNota.aprobado);
      expect(result.estadoObjetivo, EstadoObjetivoNota.asegurado);
      expect(result.promedioNecesarioRestante, isNull);
    });

    test('directo al 100 % queda evaluado y reprobado', () {
      final result = service.calcular(
        evaluaciones: [item('final', 100, grade: 3.9)],
        configuracion: config,
        objetivo: 3.5,
      );

      expect(result.estadoAcademico, EstadoAcademicoNota.reprobado);
      expect(result.estaFinalizada, isTrue);
      expect(result.pesoPendiente, 0);
      expect(result.promedioNecesarioRestante, isNull);
    });
  });

  group('presentación y examen final', () {
    ConfiguracionCalculoAsignatura scheme(double presentation, double exam) {
      return ConfiguracionCalculoAsignatura(
        asignaturaId: 'subject',
        esquema: EsquemaCalculoNotas.presentacionExamen,
        pesoPresentacion: presentation,
        pesoExamen: exam,
        evaluacionExamenId: 'final',
      );
    }

    test('calcula nota de presentación y fórmula 60/40', () {
      final result = service.calcular(
        evaluaciones: [
          item('u1', 30, grade: 6),
          item('u2', 30, grade: 6),
          item('project', 40, grade: 6),
          item('final', 0, grade: 5),
        ],
        configuracion: config,
        configuracionAsignatura: scheme(60, 40),
        objetivo: 4,
      );

      expect(result.notaPresentacion, 6);
      expect(result.notaExamen, 5);
      expect(result.resultadoFinalProyectado, closeTo(5.6, 0.000001));
      expect(result.aportePresentacion, 3.6);
      expect(result.aporteExamen, 2);
    });

    test('respeta una configuración 70/30', () {
      final result = service.calcular(
        evaluaciones: [
          item('coursework', 100, grade: 6),
          item('final', 0, grade: 4),
        ],
        configuracion: config,
        configuracionAsignatura: scheme(70, 30),
        objetivo: 4,
      );
      expect(result.resultadoFinalProyectado, closeTo(5.4, 0.000001));
    });

    test('completo prioriza nota final y estado académico', () {
      final result = service.calcular(
        evaluaciones: [
          item('coursework', 100, grade: 5.8),
          item('final', 0, grade: 4.5),
        ],
        configuracion: config,
        configuracionAsignatura: scheme(60, 40),
        objetivo: 6,
      );

      expect(result.resultadoFinalProyectado, closeTo(5.28, 0.000001));
      expect(result.estadoAcademico, EstadoAcademicoNota.aprobado);
      expect(result.estaFinalizada, isTrue);
      expect(result.evaluacionesPendientes, 0);
      expect(result.notaNecesariaExamen, isNull);
      expect(result.promedioNecesarioRestante, isNull);
      expect(result.estadoObjetivo, EstadoObjetivoNota.imposible);
    });

    test('calcula la nota necesaria en un examen pendiente', () {
      final result = service.calcular(
        evaluaciones: [item('coursework', 100, grade: 5.8), item('final', 0)],
        configuracion: config,
        configuracionAsignatura: scheme(60, 40),
        objetivo: 5,
      );
      expect(result.notaExamen, isNull);
      expect(result.notaNecesariaExamen, closeTo(3.8, 0.000001));
    });

    test('detecta objetivo imposible y aprobación asegurada', () {
      final impossible = service.calcular(
        evaluaciones: [item('coursework', 100, grade: 1), item('final', 0)],
        configuracion: config,
        configuracionAsignatura: scheme(60, 40),
        objetivo: 7,
      );
      final secured = service.calcular(
        evaluaciones: [item('coursework', 100, grade: 7), item('final', 0)],
        configuracion: config,
        configuracionAsignatura: scheme(60, 40),
        objetivo: 4,
      );
      expect(impossible.estadoObjetivo, EstadoObjetivoNota.imposible);
      expect(secured.estadoObjetivo, EstadoObjetivoNota.asegurado);
    });

    test('combina escenarios internos y de examen', () {
      final result = service.calcular(
        evaluaciones: [
          item('u1', 50, grade: 5.7),
          item('u2', 50, hypothetical: 5.7),
          item('final', 0, hypothetical: 4.5),
        ],
        configuracion: config,
        configuracionAsignatura: scheme(60, 40),
        objetivo: 5,
      );
      expect(result.notaPresentacion, closeTo(5.7, 0.000001));
      expect(result.notaExamen, 4.5);
      expect(result.resultadoFinalProyectado, closeTo(5.22, 0.000001));
    });

    test('calcula promedio interno para una presentación objetivo', () {
      final result = service.calcular(
        evaluaciones: [
          item('u1', 50, grade: 5),
          item('u2', 50),
          item('final', 0),
        ],
        configuracion: config,
        configuracionAsignatura: scheme(60, 40),
        objetivoPresentacion: 5.5,
        objetivo: 4,
      );
      expect(result.promedioNecesarioPresentacion, 6);
    });
  });
}
