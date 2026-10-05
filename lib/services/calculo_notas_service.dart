import 'dart:math' as math;

import '../models/nota.dart';

class EntradaCalculoNota {
  const EntradaCalculoNota({
    required this.id,
    required this.nombre,
    this.ponderacion,
    this.notaReal,
    this.notaHipotetica,
  });

  final String id;
  final String nombre;
  final double? ponderacion;
  final double? notaReal;
  final double? notaHipotetica;

  double? get notaEfectiva => notaReal ?? notaHipotetica;
  bool get esHipotetica => notaReal == null && notaHipotetica != null;
}

enum EstadoPonderacionesNotas {
  sinEvaluaciones,
  incompletas,
  validas,
  excedidas,
}

enum EstadoObjetivoNota { sinDatos, asegurado, alcanzable, exigente, imposible }

enum EstadoAcademicoNota { sinDatos, enCurso, aprobado, reprobado }

enum AlertaAcademicaNota {
  configuracionIncompleta,
  sinCalificaciones,
  estable,
  necesitaMejorar,
  objetivoExigente,
  objetivoImposible,
  objetivoAsegurado,
}

class ResultadoCalculoNotas {
  const ResultadoCalculoNotas({
    required this.esValido,
    required this.errores,
    required this.estadoPonderaciones,
    required this.pesoConfigurado,
    required this.pesoEvaluado,
    required this.pesoPendiente,
    required this.pesoPendienteConfigurado,
    required this.pesoSinDistribuir,
    required this.aporteAcumulado,
    required this.aporteHipotetico,
    required this.promedioParcial,
    required this.resultadoFinalProyectado,
    required this.minimoFinalPosible,
    required this.maximoFinalPosible,
    required this.promedioNecesarioRestante,
    required this.notaNecesariaUnica,
    required this.evaluacionesPendientes,
    required this.estadoAcademico,
    required this.estadoObjetivo,
    required this.alerta,
    this.esquema = EsquemaCalculoNotas.directo,
    this.notaPresentacion,
    this.notaExamen,
    this.pesoPresentacion = 100,
    this.pesoExamen = 0,
    this.aportePresentacion,
    this.aporteExamen,
    this.notaNecesariaExamen,
    this.promedioNecesarioPresentacion,
    this.objetivoPresentacion,
  });

  final bool esValido;
  final List<String> errores;
  final EstadoPonderacionesNotas estadoPonderaciones;
  final double pesoConfigurado;
  final double pesoEvaluado;
  final double pesoPendiente;
  final double pesoPendienteConfigurado;
  final double pesoSinDistribuir;
  final double aporteAcumulado;
  final double aporteHipotetico;
  final double? promedioParcial;
  final double? resultadoFinalProyectado;
  final double? minimoFinalPosible;
  final double? maximoFinalPosible;
  final double? promedioNecesarioRestante;
  final double? notaNecesariaUnica;
  final int evaluacionesPendientes;
  final EstadoAcademicoNota estadoAcademico;
  final EstadoObjetivoNota estadoObjetivo;
  final AlertaAcademicaNota alerta;
  final EsquemaCalculoNotas esquema;
  final double? notaPresentacion;
  final double? notaExamen;
  final double pesoPresentacion;
  final double pesoExamen;
  final double? aportePresentacion;
  final double? aporteExamen;
  final double? notaNecesariaExamen;
  final double? promedioNecesarioPresentacion;
  final double? objetivoPresentacion;

  bool get estaFinalizada =>
      estadoAcademico == EstadoAcademicoNota.aprobado ||
      estadoAcademico == EstadoAcademicoNota.reprobado;

  bool get estaAprobada => estadoAcademico == EstadoAcademicoNota.aprobado;

  Map<String, Object?> toStructuredMap() {
    return {
      'calculoValido': esValido,
      'errores': errores,
      'estadoPonderaciones': estadoPonderaciones.name,
      'porcentajeConfigurado': pesoConfigurado,
      'porcentajeEvaluado': pesoEvaluado,
      'porcentajePendiente': pesoPendiente,
      'porcentajeSinDistribuir': pesoSinDistribuir,
      'aporteAcumuladoFinal': aporteAcumulado,
      'promedioParcialNormalizado': promedioParcial,
      'resultadoFinalProyectado': resultadoFinalProyectado,
      'minimoFinalPosible': minimoFinalPosible,
      'maximoFinalPosible': maximoFinalPosible,
      'promedioNecesarioRestante': promedioNecesarioRestante,
      'notaNecesariaSiQuedaUna': notaNecesariaUnica,
      'evaluacionesPendientes': evaluacionesPendientes,
      'estadoAcademico': estadoAcademico.name,
      'evaluado': estaFinalizada,
      'notaFinalDefinitiva': estaFinalizada ? resultadoFinalProyectado : null,
      'estadoObjetivo': estadoObjetivo.name,
      'alertaAcademica': alerta.name,
      'esquemaCalculo': esquema.valorPersistencia,
      'notaPresentacion': notaPresentacion,
      'notaExamen': notaExamen,
      'pesoPresentacion': pesoPresentacion,
      'pesoExamen': pesoExamen,
      'aportePresentacion': aportePresentacion,
      'aporteExamen': aporteExamen,
      'notaNecesariaExamen': notaNecesariaExamen,
      'promedioNecesarioPresentacion': promedioNecesarioPresentacion,
      'objetivoPresentacion': objetivoPresentacion,
    };
  }
}

class CalculoNotasService {
  const CalculoNotasService();

  static const double tolerancia = 0.000001;

  /// Un objetivo se considera exigente cuando pide al menos el 75 % del
  /// recorrido entre la nota mínima y la máxima en el peso restante.
  static const double umbralObjetivoExigente = 0.75;

  ResultadoCalculoNotas calcular({
    required List<EntradaCalculoNota> evaluaciones,
    required ConfiguracionNotas configuracion,
    double? objetivo,
    ConfiguracionCalculoAsignatura? configuracionAsignatura,
    double? objetivoPresentacion,
    double? notaPresentacionHipotetica,
    double? notaExamenHipotetica,
  }) {
    final calculoAsignatura =
        configuracionAsignatura ??
        const ConfiguracionCalculoAsignatura(asignaturaId: 'directo');
    if (!calculoAsignatura.usaExamenFinal) {
      return _calcularDirecto(
        evaluaciones: evaluaciones,
        configuracion: configuracion,
        objetivo: objetivo,
      );
    }
    return _calcularPresentacionExamen(
      evaluaciones: evaluaciones,
      configuracion: configuracion,
      objetivo: objetivo,
      objetivoPresentacion:
          objetivoPresentacion ?? configuracion.notaAprobacion,
      calculoAsignatura: calculoAsignatura,
      notaPresentacionHipotetica: notaPresentacionHipotetica,
      notaExamenHipotetica: notaExamenHipotetica,
    );
  }

  ResultadoCalculoNotas _calcularDirecto({
    required List<EntradaCalculoNota> evaluaciones,
    required ConfiguracionNotas configuracion,
    double? objetivo,
  }) {
    final List<String> errores = [];

    if (!configuracion.esValida) {
      errores.add('configuracion_escala_invalida');
    }
    if (objetivo != null &&
        (!objetivo.isFinite ||
            objetivo < configuracion.notaMinima ||
            objetivo > configuracion.notaMaxima)) {
      errores.add('objetivo_fuera_de_escala');
    }

    double pesoConfigurado = 0;
    double pesoEvaluado = 0;
    double pesoPendienteConfigurado = 0;
    double aporteReal = 0;
    double aporteHipotetico = 0;
    int pendientes = 0;
    int pendientesEfectivasConPeso = 0;

    for (final EntradaCalculoNota evaluacion in evaluaciones) {
      final double? peso = evaluacion.ponderacion;
      final double? real = evaluacion.notaReal;
      final double? hipotetica = evaluacion.notaHipotetica;

      if (peso != null && (!peso.isFinite || peso < 0 || peso > 100)) {
        errores.add('ponderacion_invalida:${evaluacion.id}');
      }
      for (final double? nota in [real, hipotetica]) {
        if (nota != null &&
            (!nota.isFinite ||
                nota < configuracion.notaMinima ||
                nota > configuracion.notaMaxima)) {
          errores.add('nota_fuera_de_escala:${evaluacion.id}');
        }
      }
      if (real != null && hipotetica != null) {
        errores.add('escenario_sobre_nota_real:${evaluacion.id}');
      }

      if (peso != null && peso.isFinite && peso >= 0 && peso <= 100) {
        pesoConfigurado += peso;
      }

      if (real == null) {
        pendientes++;
        if (peso != null && peso > tolerancia) {
          pesoPendienteConfigurado += peso;
        }
      }

      if (real == null &&
          hipotetica == null &&
          peso != null &&
          peso > tolerancia) {
        pendientesEfectivasConPeso++;
      }

      if (peso == null || peso <= tolerancia) continue;

      if (real != null) {
        pesoEvaluado += peso;
        aporteReal += real * peso / 100;
      } else if (hipotetica != null) {
        aporteHipotetico += hipotetica * peso / 100;
      }
    }

    if (pesoConfigurado > 100 + tolerancia) {
      errores.add('ponderaciones_exceden_100');
    }

    final EstadoPonderacionesNotas estadoPonderaciones;
    if (evaluaciones.isEmpty) {
      estadoPonderaciones = EstadoPonderacionesNotas.sinEvaluaciones;
    } else if (pesoConfigurado > 100 + tolerancia) {
      estadoPonderaciones = EstadoPonderacionesNotas.excedidas;
    } else if ((pesoConfigurado - 100).abs() <= tolerancia &&
        evaluaciones.every((item) => item.ponderacion != null)) {
      estadoPonderaciones = EstadoPonderacionesNotas.validas;
    } else {
      estadoPonderaciones = EstadoPonderacionesNotas.incompletas;
    }

    final bool valido = errores.isEmpty;
    final double pesoPendiente = math.max(0, 100 - pesoEvaluado);
    final double pesoSinDistribuir = math.max(0, 100 - pesoConfigurado);
    final double aporteAcumulado = aporteReal + aporteHipotetico;
    final double pesoConNota = evaluaciones.fold<double>(0, (suma, item) {
      final peso = item.ponderacion ?? 0;
      return suma + (item.notaEfectiva != null && peso > 0 ? peso : 0);
    });

    final double? promedioParcial = valido && pesoConNota > tolerancia
        ? aporteAcumulado / (pesoConNota / 100)
        : null;
    final double pesoRestanteEscenario = math.max(0, 100 - pesoConNota);
    final double? minimoFinal = valido
        ? aporteAcumulado +
              configuracion.notaMinima * pesoRestanteEscenario / 100
        : null;
    final double? maximoFinal = valido
        ? aporteAcumulado +
              configuracion.notaMaxima * pesoRestanteEscenario / 100
        : null;

    final double? objetivoEfectivo =
        objetivo != null &&
            objetivo.isFinite &&
            objetivo >= configuracion.notaMinima &&
            objetivo <= configuracion.notaMaxima
        ? objetivo
        : null;
    double? requerido;
    EstadoObjetivoNota estadoObjetivo = EstadoObjetivoNota.sinDatos;

    if (valido && objetivoEfectivo != null) {
      if (pesoRestanteEscenario <= tolerancia) {
        estadoObjetivo = aporteAcumulado >= objetivoEfectivo - tolerancia
            ? EstadoObjetivoNota.asegurado
            : EstadoObjetivoNota.imposible;
      } else if (minimoFinal! >= objetivoEfectivo - tolerancia) {
        estadoObjetivo = EstadoObjetivoNota.asegurado;
        requerido = configuracion.notaMinima;
      } else if (maximoFinal! < objetivoEfectivo - tolerancia) {
        estadoObjetivo = EstadoObjetivoNota.imposible;
        if (pesoRestanteEscenario > tolerancia) {
          requerido =
              (objetivoEfectivo - aporteAcumulado) /
              (pesoRestanteEscenario / 100);
        }
      } else if (pesoRestanteEscenario > tolerancia) {
        requerido =
            (objetivoEfectivo - aporteAcumulado) /
            (pesoRestanteEscenario / 100);
        final double umbral =
            configuracion.notaMinima +
            (configuracion.notaMaxima - configuracion.notaMinima) *
                umbralObjetivoExigente;
        estadoObjetivo = requerido >= umbral
            ? EstadoObjetivoNota.exigente
            : EstadoObjetivoNota.alcanzable;
      }
    }

    final bool escenarioCompleto =
        valido &&
        estadoPonderaciones == EstadoPonderacionesNotas.validas &&
        pesoRestanteEscenario <= tolerancia;
    final double? resultadoFinal = escenarioCompleto ? aporteAcumulado : null;
    final bool evaluadoConNotasReales =
        escenarioCompleto &&
        evaluaciones.isNotEmpty &&
        evaluaciones.every((item) => item.notaReal != null);
    final EstadoAcademicoNota estadoAcademico = evaluadoConNotasReales
        ? resultadoFinal! >= configuracion.notaAprobacion - tolerancia
              ? EstadoAcademicoNota.aprobado
              : EstadoAcademicoNota.reprobado
        : pesoEvaluado <= tolerancia
        ? EstadoAcademicoNota.sinDatos
        : EstadoAcademicoNota.enCurso;
    final double? notaUnica =
        valido &&
            estadoPonderaciones == EstadoPonderacionesNotas.validas &&
            pendientesEfectivasConPeso == 1 &&
            objetivoEfectivo != null
        ? requerido
        : null;

    final AlertaAcademicaNota alerta;
    if (!valido || estadoPonderaciones != EstadoPonderacionesNotas.validas) {
      alerta = AlertaAcademicaNota.configuracionIncompleta;
    } else if (pesoEvaluado <= tolerancia) {
      alerta = AlertaAcademicaNota.sinCalificaciones;
    } else {
      alerta = switch (estadoObjetivo) {
        EstadoObjetivoNota.asegurado => AlertaAcademicaNota.objetivoAsegurado,
        EstadoObjetivoNota.imposible => AlertaAcademicaNota.objetivoImposible,
        EstadoObjetivoNota.exigente => AlertaAcademicaNota.objetivoExigente,
        EstadoObjetivoNota.alcanzable =>
          requerido != null &&
                  promedioParcial != null &&
                  requerido > promedioParcial + tolerancia
              ? AlertaAcademicaNota.necesitaMejorar
              : AlertaAcademicaNota.estable,
        EstadoObjetivoNota.sinDatos => AlertaAcademicaNota.estable,
      };
    }

    return ResultadoCalculoNotas(
      esValido: valido,
      errores: List.unmodifiable(errores),
      estadoPonderaciones: estadoPonderaciones,
      pesoConfigurado: pesoConfigurado,
      pesoEvaluado: pesoEvaluado,
      pesoPendiente: pesoPendiente,
      pesoPendienteConfigurado: pesoPendienteConfigurado,
      pesoSinDistribuir: pesoSinDistribuir,
      aporteAcumulado: aporteAcumulado,
      aporteHipotetico: aporteHipotetico,
      promedioParcial: promedioParcial,
      resultadoFinalProyectado: resultadoFinal,
      minimoFinalPosible: minimoFinal,
      maximoFinalPosible: maximoFinal,
      promedioNecesarioRestante: requerido,
      notaNecesariaUnica: notaUnica,
      evaluacionesPendientes: pendientes,
      estadoAcademico: estadoAcademico,
      estadoObjetivo: estadoObjetivo,
      alerta: alerta,
    );
  }

  ResultadoCalculoNotas _calcularPresentacionExamen({
    required List<EntradaCalculoNota> evaluaciones,
    required ConfiguracionNotas configuracion,
    required ConfiguracionCalculoAsignatura calculoAsignatura,
    required double objetivoPresentacion,
    double? notaPresentacionHipotetica,
    double? notaExamenHipotetica,
    double? objetivo,
  }) {
    final examId = calculoAsignatura.evaluacionExamenId;
    final examMatches = evaluaciones
        .where((item) => item.id == examId)
        .toList();
    final internas = evaluaciones.where((item) => item.id != examId).toList();
    final presentacion = _calcularDirecto(
      evaluaciones: internas,
      configuracion: configuracion,
      objetivo: objetivoPresentacion,
    );
    final errores = <String>[...presentacion.errores];
    if (!calculoAsignatura.esValida) {
      errores.add('configuracion_presentacion_examen_invalida');
    }
    if (examMatches.length != 1) {
      errores.add('evaluacion_examen_no_disponible');
    }
    for (final scenario in [notaPresentacionHipotetica, notaExamenHipotetica]) {
      if (scenario != null &&
          (!scenario.isFinite ||
              scenario < configuracion.notaMinima ||
              scenario > configuracion.notaMaxima)) {
        errores.add('escenario_superior_fuera_de_escala');
      }
    }

    final exam = examMatches.length == 1 ? examMatches.single : null;
    final examGrade = exam?.notaEfectiva ?? notaExamenHipotetica;
    final presentationGrade =
        notaPresentacionHipotetica ??
        (presentacion.estadoPonderaciones == EstadoPonderacionesNotas.validas
            ? presentacion.resultadoFinalProyectado
            : null);
    final presentationWeight = calculoAsignatura.pesoPresentacion;
    final examWeight = calculoAsignatura.pesoExamen;
    final presentationContribution = presentationGrade == null
        ? null
        : presentationGrade * presentationWeight / 100;
    final examContribution = examGrade == null
        ? null
        : examGrade * examWeight / 100;
    final finalGrade =
        presentationContribution != null &&
            examContribution != null &&
            errores.isEmpty
        ? presentationContribution + examContribution
        : null;

    final minPresentation = presentacion.minimoFinalPosible;
    final maxPresentation = presentacion.maximoFinalPosible;
    final minExam = examGrade ?? configuracion.notaMinima;
    final maxExam = examGrade ?? configuracion.notaMaxima;
    final minFinal = minPresentation == null || errores.isNotEmpty
        ? null
        : minPresentation * presentationWeight / 100 +
              minExam * examWeight / 100;
    final maxFinal = maxPresentation == null || errores.isNotEmpty
        ? null
        : maxPresentation * presentationWeight / 100 +
              maxExam * examWeight / 100;

    double? neededExam;
    final effectiveTarget =
        objetivo != null &&
            objetivo.isFinite &&
            objetivo >= configuracion.notaMinima &&
            objetivo <= configuracion.notaMaxima
        ? objetivo
        : null;
    if (effectiveTarget != null &&
        exam?.notaReal == null &&
        presentationGrade != null &&
        examWeight > tolerancia) {
      neededExam =
          (effectiveTarget - presentationGrade * presentationWeight / 100) /
          (examWeight / 100);
    }

    var objectiveState = EstadoObjetivoNota.sinDatos;
    if (effectiveTarget != null && minFinal != null && maxFinal != null) {
      if (minFinal >= effectiveTarget - tolerancia) {
        objectiveState = EstadoObjetivoNota.asegurado;
      } else if (maxFinal < effectiveTarget - tolerancia) {
        objectiveState = EstadoObjetivoNota.imposible;
      } else {
        final demandingThreshold =
            configuracion.notaMinima +
            (configuracion.notaMaxima - configuracion.notaMinima) *
                umbralObjetivoExigente;
        objectiveState = neededExam != null && neededExam >= demandingThreshold
            ? EstadoObjetivoNota.exigente
            : EstadoObjetivoNota.alcanzable;
      }
    }

    final valid =
        errores.isEmpty &&
        presentacion.estadoPonderaciones == EstadoPonderacionesNotas.validas;
    final alert = !valid
        ? AlertaAcademicaNota.configuracionIncompleta
        : presentacion.pesoEvaluado <= tolerancia && examGrade == null
        ? AlertaAcademicaNota.sinCalificaciones
        : switch (objectiveState) {
            EstadoObjetivoNota.asegurado =>
              AlertaAcademicaNota.objetivoAsegurado,
            EstadoObjetivoNota.imposible =>
              AlertaAcademicaNota.objetivoImposible,
            EstadoObjetivoNota.exigente => AlertaAcademicaNota.objetivoExigente,
            EstadoObjetivoNota.alcanzable =>
              AlertaAcademicaNota.necesitaMejorar,
            EstadoObjetivoNota.sinDatos => AlertaAcademicaNota.estable,
          };
    final int pendientesReales =
        presentacion.evaluacionesPendientes +
        (exam == null || exam.notaReal == null ? 1 : 0);
    final bool evaluadoConNotasReales =
        valid &&
        finalGrade != null &&
        evaluaciones.isNotEmpty &&
        evaluaciones.every((item) => item.notaReal != null);
    final EstadoAcademicoNota estadoAcademico = evaluadoConNotasReales
        ? finalGrade >= configuracion.notaAprobacion - tolerancia
              ? EstadoAcademicoNota.aprobado
              : EstadoAcademicoNota.reprobado
        : presentacion.pesoEvaluado <= tolerancia && exam?.notaReal == null
        ? EstadoAcademicoNota.sinDatos
        : EstadoAcademicoNota.enCurso;

    return ResultadoCalculoNotas(
      esValido: valid,
      errores: List.unmodifiable(errores),
      estadoPonderaciones: presentacion.estadoPonderaciones,
      pesoConfigurado: presentacion.pesoConfigurado,
      pesoEvaluado: presentacion.pesoEvaluado,
      pesoPendiente: presentacion.pesoPendiente,
      pesoPendienteConfigurado: presentacion.pesoPendienteConfigurado,
      pesoSinDistribuir: presentacion.pesoSinDistribuir,
      aporteAcumulado:
          (presentacion.aporteAcumulado * presentationWeight / 100) +
          (examContribution ?? 0),
      aporteHipotetico:
          (presentacion.aporteHipotetico * presentationWeight / 100) +
          (exam?.esHipotetica == true ? examContribution ?? 0 : 0),
      promedioParcial: presentacion.promedioParcial,
      resultadoFinalProyectado: finalGrade,
      minimoFinalPosible: minFinal,
      maximoFinalPosible: maxFinal,
      promedioNecesarioRestante: presentacion.promedioNecesarioRestante,
      notaNecesariaUnica: presentacion.notaNecesariaUnica,
      evaluacionesPendientes: pendientesReales,
      estadoAcademico: estadoAcademico,
      estadoObjetivo: objectiveState,
      alerta: alert,
      esquema: EsquemaCalculoNotas.presentacionExamen,
      notaPresentacion: presentationGrade,
      notaExamen: examGrade,
      pesoPresentacion: presentationWeight,
      pesoExamen: examWeight,
      aportePresentacion: presentationContribution,
      aporteExamen: examContribution,
      notaNecesariaExamen: neededExam,
      promedioNecesarioPresentacion: presentacion.promedioNecesarioRestante,
      objetivoPresentacion: objetivoPresentacion,
    );
  }

  double redondear(double valor, ConfiguracionNotas configuracion) {
    if (!valor.isFinite) return valor;
    final double factor = math.pow(10, configuracion.decimales).toDouble();
    return switch (configuracion.politicaRedondeo) {
      PoliticaRedondeoNotas.masCercano =>
        (valor * factor + tolerancia).round() / factor,
      PoliticaRedondeoNotas.truncar => (valor * factor).truncate() / factor,
    };
  }
}
