import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/notificacion_app.dart';
import '../models/tarea.dart';

class NotificationFeedService {
  NotificationFeedService._();

  static final NotificationFeedService instance = NotificationFeedService._();

  List<NotificacionApp> generar({
    required List<Asignatura> asignaturas,
    required List<Tarea> tareas,
    required List<Evaluacion> evaluaciones,
    required bool spanish,
    DateTime? now,
  }) {
    final DateTime ahora = now ?? DateTime.now();

    final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day);

    final List<NotificacionApp> resultado = [
      ..._generarClases(
        asignaturas: asignaturas,
        spanish: spanish,
        ahora: ahora,
        hoy: hoy,
      ),
      ..._generarTareas(
        tareas: tareas,
        asignaturas: asignaturas,
        spanish: spanish,
        ahora: ahora,
        hoy: hoy,
      ),
      ..._generarEvaluaciones(
        evaluaciones: evaluaciones,
        asignaturas: asignaturas,
        spanish: spanish,
        hoy: hoy,
      ),
    ];

    resultado.sort((a, b) {
      if (a.grupo != b.grupo) {
        return a.grupo == GrupoNotificacionApp.reciente ? -1 : 1;
      }

      if (a.grupo == GrupoNotificacionApp.anterior) {
        return b.momentoOrden.compareTo(a.momentoOrden);
      }

      return a.momentoOrden.compareTo(b.momentoOrden);
    });

    return resultado;
  }

  // =========================================================
  // CLASES
  // =========================================================

  List<NotificacionApp> _generarClases({
    required List<Asignatura> asignaturas,
    required bool spanish,
    required DateTime ahora,
    required DateTime hoy,
  }) {
    final DiaSemana? dia = _diaSemana(hoy.weekday);

    if (dia == null) {
      return [];
    }

    final int minutosAhora = (ahora.hour * 60) + ahora.minute;

    final List<NotificacionApp> resultado = [];

    for (final Asignatura asignatura in asignaturas) {
      for (int index = 0; index < asignatura.horario.length; index++) {
        final BloqueHorario bloque = asignatura.horario[index];

        if (bloque.dia != dia) {
          continue;
        }

        final int inicio = _horaAMinutos(bloque.horaInicio);

        final int fin = _horaAMinutos(bloque.horaFin);

        final int diferencia = inicio - minutosAhora;

        final String ubicacion = _ubicacionClase(asignatura, bloque, spanish);

        late final String titulo;
        late final String mensaje;
        late final GrupoNotificacionApp grupo;

        if (diferencia > 0 && diferencia <= 60) {
          titulo = spanish
              ? 'Tu clase comienza pronto'
              : 'Your class starts soon';

          mensaje = spanish
              ? '${asignatura.nombre} comienza a las '
                    '${bloque.horaInicio}$ubicacion'
              : '${asignatura.nombre} starts at '
                    '${bloque.horaInicio}$ubicacion';

          grupo = GrupoNotificacionApp.reciente;
        } else if (diferencia > 60) {
          titulo = spanish
              ? 'Clase programada para hoy'
              : 'Class scheduled for today';

          mensaje = spanish
              ? '${asignatura.nombre} comienza a las '
                    '${bloque.horaInicio}$ubicacion'
              : '${asignatura.nombre} starts at '
                    '${bloque.horaInicio}$ubicacion';

          grupo = GrupoNotificacionApp.reciente;
        } else {
          titulo = spanish ? 'Clase de hoy' : 'Today\'s class';

          mensaje = spanish
              ? '${asignatura.nombre} estaba programada de '
                    '${bloque.horaInicio} a ${bloque.horaFin}$ubicacion'
              : '${asignatura.nombre} was scheduled from '
                    '${bloque.horaInicio} to ${bloque.horaFin}$ubicacion';

          grupo = minutosAhora > fin
              ? GrupoNotificacionApp.anterior
              : GrupoNotificacionApp.reciente;
        }

        resultado.add(
          NotificacionApp(
            id:
                'clase-${asignatura.id}-'
                '${_fechaId(hoy)}-${bloque.horaInicio}',
            tipo: TipoNotificacionApp.clase,
            grupo: grupo,
            titulo: titulo,
            mensaje: mensaje,
            fechaEvento: hoy,
            horaEvento: bloque.horaInicio,
            referenciaId: asignatura.id,
            asignaturaId: asignatura.id,
            bloqueIndex: index,
          ),
        );
      }
    }

    return resultado;
  }

  // =========================================================
  // TAREAS
  // =========================================================

  List<NotificacionApp> _generarTareas({
    required List<Tarea> tareas,
    required List<Asignatura> asignaturas,
    required bool spanish,
    required DateTime ahora,
    required DateTime hoy,
  }) {
    final List<NotificacionApp> resultado = [];

    for (final Tarea tarea in tareas) {
      if (tarea.completada) {
        continue;
      }

      final DateTime? fechaOriginal = tarea.fechaEntrega;

      if (fechaOriginal == null) {
        continue;
      }

      final DateTime fecha = DateTime(
        fechaOriginal.year,
        fechaOriginal.month,
        fechaOriginal.day,
      );

      final int diferencia = fecha.difference(hoy).inDays;

      // El centro se enfoca en entregas relevantes:
      // vencidas durante la última semana o próximas 7 días.
      if (diferencia < -7 || diferencia > 7) {
        continue;
      }

      final bool vencidaHoy =
          diferencia == 0 && _horaYaPaso(tarea.horaEntrega, ahora);

      final bool vencida = diferencia < 0 || vencidaHoy;

      final String asignatura = _nombreAsignatura(
        tarea.asignaturaId,
        asignaturas,
        spanish,
        generalTask: true,
      );

      late final String titulo;

      if (vencida) {
        titulo = spanish ? 'Tarea vencida' : 'Overdue task';
      } else if (diferencia == 0) {
        titulo = spanish ? 'Tarea vence hoy' : 'Task due today';
      } else if (diferencia == 1) {
        titulo = spanish ? 'Tarea vence mañana' : 'Task due tomorrow';
      } else {
        titulo = spanish ? 'Próxima entrega' : 'Upcoming assignment';
      }

      final String hora = tarea.horaEntrega?.trim() ?? '';

      final String mensaje;

      if (spanish) {
        mensaje = hora.isEmpty
            ? '${tarea.titulo} · $asignatura.'
            : '${tarea.titulo} · $asignatura · $hora.';
      } else {
        mensaje = hora.isEmpty
            ? '${tarea.titulo} · $asignatura.'
            : '${tarea.titulo} · $asignatura · $hora.';
      }

      resultado.add(
        NotificacionApp(
          id: 'tarea-${tarea.id}',
          tipo: TipoNotificacionApp.tarea,
          grupo: vencida
              ? GrupoNotificacionApp.anterior
              : GrupoNotificacionApp.reciente,
          titulo: titulo,
          mensaje: mensaje,
          fechaEvento: fecha,
          horaEvento: tarea.horaEntrega,
          referenciaId: tarea.id,
          asignaturaId: tarea.asignaturaId,
        ),
      );
    }

    return resultado;
  }

  // =========================================================
  // EVALUACIONES
  // =========================================================

  List<NotificacionApp> _generarEvaluaciones({
    required List<Evaluacion> evaluaciones,
    required List<Asignatura> asignaturas,
    required bool spanish,
    required DateTime hoy,
  }) {
    final List<NotificacionApp> resultado = [];

    for (final Evaluacion evaluacion in evaluaciones) {
      final DateTime fecha = DateTime(
        evaluacion.fecha.year,
        evaluacion.fecha.month,
        evaluacion.fecha.day,
      );

      final int diferencia = fecha.difference(hoy).inDays;

      // Mostramos evaluaciones de hoy y las próximas 7 jornadas.
      if (diferencia < 0 || diferencia > 7) {
        continue;
      }

      final String asignatura = _nombreAsignatura(
        evaluacion.asignaturaId,
        asignaturas,
        spanish,
      );

      final String tipo = _tipoEvaluacion(evaluacion.tipo, spanish);

      late final String titulo;

      if (diferencia == 0) {
        titulo = spanish ? 'Evaluación hoy' : 'Evaluation today';
      } else if (diferencia == 1) {
        titulo = spanish ? 'Evaluación mañana' : 'Evaluation tomorrow';
      } else {
        titulo = spanish ? 'Evaluación próxima' : 'Upcoming evaluation';
      }

      final String hora = evaluacion.hora?.trim() ?? '';

      final String mensaje = hora.isEmpty
          ? '${evaluacion.titulo} · $tipo · $asignatura.'
          : '${evaluacion.titulo} · $tipo · $asignatura · $hora.';

      resultado.add(
        NotificacionApp(
          id: 'evaluacion-${evaluacion.id}',
          tipo: TipoNotificacionApp.evaluacion,
          grupo: GrupoNotificacionApp.reciente,
          titulo: titulo,
          mensaje: mensaje,
          fechaEvento: fecha,
          horaEvento: evaluacion.hora,
          referenciaId: evaluacion.id,
          asignaturaId: evaluacion.asignaturaId,
        ),
      );
    }

    return resultado;
  }

  // =========================================================
  // HELPERS
  // =========================================================

  DiaSemana? _diaSemana(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return DiaSemana.lunes;
      case DateTime.tuesday:
        return DiaSemana.martes;
      case DateTime.wednesday:
        return DiaSemana.miercoles;
      case DateTime.thursday:
        return DiaSemana.jueves;
      case DateTime.friday:
        return DiaSemana.viernes;
      case DateTime.saturday:
        return DiaSemana.sabado;
      case DateTime.sunday:
        return null;
    }

    return null;
  }

  int _horaAMinutos(String hora) {
    final List<String> partes = hora.split(':');

    if (partes.length != 2) {
      return 0;
    }

    final int horas = int.tryParse(partes[0]) ?? 0;

    final int minutos = int.tryParse(partes[1]) ?? 0;

    return (horas * 60) + minutos;
  }

  bool _horaYaPaso(String? value, DateTime ahora) {
    final String hora = value?.trim() ?? '';

    if (hora.isEmpty) {
      return false;
    }

    final List<String> partes = hora.split(':');

    if (partes.length != 2) {
      return false;
    }

    final int? horas = int.tryParse(partes[0]);

    final int? minutos = int.tryParse(partes[1]);

    if (horas == null || minutos == null) {
      return false;
    }

    final DateTime limite = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      horas,
      minutos,
    ).add(const Duration(minutes: 1));

    return !ahora.isBefore(limite);
  }

  String _ubicacionClase(
    Asignatura asignatura,
    BloqueHorario bloque,
    bool spanish,
  ) {
    final String salaBloque = bloque.sala?.trim() ?? '';

    final String salaAsignatura = asignatura.sala?.trim() ?? '';

    final String sala = salaBloque.isNotEmpty ? salaBloque : salaAsignatura;

    if (sala.isEmpty) {
      return '.';
    }

    if (spanish) {
      final String salaTexto = sala.toLowerCase().startsWith('sala ')
          ? sala
          : 'sala $sala';

      return ' en $salaTexto.';
    }

    final String roomText = sala.toLowerCase().startsWith('room ')
        ? sala
        : 'room $sala';

    return ' in $roomText.';
  }

  String _nombreAsignatura(
    String? id,
    List<Asignatura> asignaturas,
    bool spanish, {
    bool generalTask = false,
  }) {
    final String limpio = id?.trim() ?? '';

    if (limpio.isEmpty) {
      if (generalTask) {
        return spanish ? 'Tarea general' : 'General task';
      }

      return spanish ? 'Sin asignatura' : 'No subject';
    }

    for (final Asignatura asignatura in asignaturas) {
      if (asignatura.id == limpio) {
        return asignatura.nombre;
      }
    }

    return spanish ? 'Asignatura no disponible' : 'Subject unavailable';
  }

  String _tipoEvaluacion(TipoEvaluacion tipo, bool spanish) {
    if (spanish) {
      switch (tipo) {
        case TipoEvaluacion.prueba:
          return 'Prueba';
        case TipoEvaluacion.examen:
          return 'Examen';
        case TipoEvaluacion.control:
          return 'Control';
        case TipoEvaluacion.quiz:
          return 'Quiz';
        case TipoEvaluacion.presentacion:
          return 'Presentación';
        case TipoEvaluacion.otro:
          return 'Otro';
      }
    }

    switch (tipo) {
      case TipoEvaluacion.prueba:
        return 'Test';
      case TipoEvaluacion.examen:
        return 'Exam';
      case TipoEvaluacion.control:
        return 'Assessment';
      case TipoEvaluacion.quiz:
        return 'Quiz';
      case TipoEvaluacion.presentacion:
        return 'Presentation';
      case TipoEvaluacion.otro:
        return 'Other';
    }
  }

  String _fechaId(DateTime fecha) {
    return '${fecha.year.toString().padLeft(4, '0')}'
        '${fecha.month.toString().padLeft(2, '0')}'
        '${fecha.day.toString().padLeft(2, '0')}';
  }
}
