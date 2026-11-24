import '../models/asignatura.dart';
import '../models/periodo_academico.dart';
import '../models/sesion_clase.dart';

enum TipoOcurrenciaClase { semanal, fechaEspecifica }

class OcurrenciaClase {
  const OcurrenciaClase({
    required this.asignatura,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.sala,
    required this.tipo,
    this.esProvisional = false,
    this.bloqueIndex,
    this.sesion,
  });

  final Asignatura asignatura;
  final DateTime fecha;
  final String horaInicio;
  final String horaFin;
  final String? sala;
  final TipoOcurrenciaClase tipo;
  final bool esProvisional;
  final int? bloqueIndex;
  final SesionClase? sesion;
}

class ConflictoOcurrenciasClase {
  const ConflictoOcurrenciasClase({
    required this.primera,
    required this.segunda,
  });

  final OcurrenciaClase primera;
  final OcurrenciaClase segunda;
}

class OcurrenciasClaseService {
  const OcurrenciasClaseService();

  List<OcurrenciaClase> obtenerParaFecha({
    required DateTime fecha,
    required List<Asignatura> asignaturas,
    required List<PeriodoAcademico> periodos,
    required List<SesionClase> sesiones,
  }) {
    final fechaNormalizada = _soloFecha(fecha);
    final periodosPorId = {for (final periodo in periodos) periodo.id: periodo};
    final asignaturasPorId = {
      for (final asignatura in asignaturas) asignatura.id: asignatura,
    };
    final resultado = <OcurrenciaClase>[];

    for (final asignatura in asignaturas) {
      final vigencia = _vigenciaAsignaturaEnFecha(
        asignatura,
        fechaNormalizada,
        periodosPorId,
      );
      if (!vigencia.vigente) {
        continue;
      }

      for (var index = 0; index < asignatura.horario.length; index++) {
        final bloque = asignatura.horario[index];
        if (_weekday(bloque.dia) != fechaNormalizada.weekday ||
            !_rangoValido(bloque.horaInicio, bloque.horaFin)) {
          continue;
        }

        resultado.add(
          OcurrenciaClase(
            asignatura: asignatura,
            fecha: fechaNormalizada,
            horaInicio: bloque.horaInicio,
            horaFin: bloque.horaFin,
            sala: _salaEfectiva(bloque.sala, asignatura.sala),
            tipo: TipoOcurrenciaClase.semanal,
            esProvisional: vigencia.provisional,
            bloqueIndex: index,
          ),
        );
      }
    }

    for (final sesion in sesiones) {
      if (!_mismaFecha(sesion.fecha, fechaNormalizada)) continue;

      final periodo = periodosPorId[sesion.periodoAcademicoId];
      final asignatura = asignaturasPorId[sesion.asignaturaId];
      if (periodo == null ||
          asignatura == null ||
          !periodo.contiene(fechaNormalizada) ||
          !_sesionPerteneceAlPeriodo(asignatura, sesion)) {
        continue;
      }

      resultado.add(
        OcurrenciaClase(
          asignatura: asignatura,
          fecha: fechaNormalizada,
          horaInicio: sesion.horaInicio,
          horaFin: sesion.horaFin,
          sala: _salaEfectiva(sesion.sala, asignatura.sala),
          tipo: TipoOcurrenciaClase.fechaEspecifica,
          sesion: sesion,
        ),
      );
    }

    resultado.sort((a, b) {
      final porHora = a.horaInicio.compareTo(b.horaInicio);
      if (porHora != 0) return porHora;
      return a.asignatura.nombre.toLowerCase().compareTo(
        b.asignatura.nombre.toLowerCase(),
      );
    });
    return List.unmodifiable(resultado);
  }

  List<ConflictoOcurrenciasClase> buscarConflictosParaFecha({
    required DateTime fecha,
    required List<Asignatura> asignaturas,
    required List<PeriodoAcademico> periodos,
    required List<SesionClase> sesiones,
  }) {
    final ocurrencias = obtenerParaFecha(
      fecha: fecha,
      asignaturas: asignaturas,
      periodos: periodos,
      sesiones: sesiones,
    );
    final conflictos = <ConflictoOcurrenciasClase>[];

    for (
      var primeraIndex = 0;
      primeraIndex < ocurrencias.length;
      primeraIndex++
    ) {
      final primera = ocurrencias[primeraIndex];
      for (
        var segundaIndex = primeraIndex + 1;
        segundaIndex < ocurrencias.length;
        segundaIndex++
      ) {
        final segunda = ocurrencias[segundaIndex];
        if (_seSuperponen(primera, segunda)) {
          conflictos.add(
            ConflictoOcurrenciasClase(primera: primera, segunda: segunda),
          );
        }
      }
    }

    return List.unmodifiable(conflictos);
  }

  ({bool vigente, bool provisional}) _vigenciaAsignaturaEnFecha(
    Asignatura asignatura,
    DateTime fecha,
    Map<String, PeriodoAcademico> periodosPorId,
  ) {
    final periodoId = asignatura.periodoAcademicoId?.trim() ?? '';
    if (periodoId.isEmpty) {
      // Compatibilidad: una asignatura heredada conserva su comportamiento
      // semanal anterior hasta que el usuario la asocie explícitamente.
      return (vigente: true, provisional: false);
    }
    final periodo = periodosPorId[periodoId];
    if (periodo == null) {
      return (vigente: false, provisional: false);
    }
    if (periodo.tieneFechasCompletas) {
      return (vigente: periodo.contiene(fecha), provisional: false);
    }

    // Sin ambos límites oficiales, el patrón semanal se restringe al año
    // académico declarado y a cualquier límite conocido. Así puede revisarse
    // en Horario/Calendario sin producir recurrencias indefinidas ni reactivar
    // períodos históricos en años posteriores.
    final vigente = fecha.year == periodo.anio && periodo.contiene(fecha);
    return (vigente: vigente, provisional: vigente);
  }

  bool _sesionPerteneceAlPeriodo(Asignatura asignatura, SesionClase sesion) {
    final periodoAsignatura = asignatura.periodoAcademicoId?.trim() ?? '';
    return periodoAsignatura.isEmpty ||
        periodoAsignatura == sesion.periodoAcademicoId;
  }

  bool _seSuperponen(OcurrenciaClase primera, OcurrenciaClase segunda) {
    final inicioPrimera = SesionClase.horaEnMinutos(primera.horaInicio);
    final finPrimera = SesionClase.horaEnMinutos(primera.horaFin);
    final inicioSegunda = SesionClase.horaEnMinutos(segunda.horaInicio);
    final finSegunda = SesionClase.horaEnMinutos(segunda.horaFin);
    if (inicioPrimera == null ||
        finPrimera == null ||
        inicioSegunda == null ||
        finSegunda == null) {
      return false;
    }
    return inicioPrimera < finSegunda && finPrimera > inicioSegunda;
  }

  bool _rangoValido(String inicio, String fin) {
    final inicioMinutos = SesionClase.horaEnMinutos(inicio);
    final finMinutos = SesionClase.horaEnMinutos(fin);
    return inicioMinutos != null &&
        finMinutos != null &&
        finMinutos > inicioMinutos;
  }

  int _weekday(DiaSemana dia) {
    return switch (dia) {
      DiaSemana.lunes => DateTime.monday,
      DiaSemana.martes => DateTime.tuesday,
      DiaSemana.miercoles => DateTime.wednesday,
      DiaSemana.jueves => DateTime.thursday,
      DiaSemana.viernes => DateTime.friday,
      DiaSemana.sabado => DateTime.saturday,
    };
  }

  String? _salaEfectiva(String? especifica, String? predeterminada) {
    final salaEspecifica = especifica?.trim() ?? '';
    if (salaEspecifica.isNotEmpty) return salaEspecifica;
    final salaPredeterminada = predeterminada?.trim() ?? '';
    return salaPredeterminada.isEmpty ? null : salaPredeterminada;
  }

  bool _mismaFecha(DateTime primera, DateTime segunda) {
    return primera.year == segunda.year &&
        primera.month == segunda.month &&
        primera.day == segunda.day;
  }

  DateTime _soloFecha(DateTime fecha) {
    return DateTime(fecha.year, fecha.month, fecha.day);
  }
}
