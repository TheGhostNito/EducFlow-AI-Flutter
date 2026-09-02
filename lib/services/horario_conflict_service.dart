import '../models/asignatura.dart';

class ConflictoHorario {
  const ConflictoHorario({
    required this.asignatura,
    required this.bloque,
    required this.bloqueIndex,
  });

  final Asignatura asignatura;
  final BloqueHorario bloque;

  /// Posición real del bloque dentro de
  /// asignatura.horario.
  final int bloqueIndex;
}

class HorarioConflictService {
  HorarioConflictService._();

  static final HorarioConflictService instance = HorarioConflictService._();

  // =========================================================
  // BUSCAR CONFLICTOS
  // =========================================================

  List<ConflictoHorario> buscarConflictos({
    required List<Asignatura> asignaturas,
    required String asignaturaId,
    required BloqueHorario bloquePropuesto,

    /// Se utiliza cuando estamos editando un bloque existente.
    ///
    /// De esta manera evitamos que el bloque choque consigo mismo.
    int? bloqueIndexIgnorar,
  }) {
    final int? inicioPropuesto = _horaAMinutos(bloquePropuesto.horaInicio);

    final int? finPropuesto = _horaAMinutos(bloquePropuesto.horaFin);

    if (inicioPropuesto == null ||
        finPropuesto == null ||
        finPropuesto <= inicioPropuesto) {
      return const [];
    }

    final List<ConflictoHorario> conflictos = [];

    for (final Asignatura asignatura in asignaturas) {
      for (int index = 0; index < asignatura.horario.length; index++) {
        final BloqueHorario bloqueExistente = asignatura.horario[index];

        // Si estamos editando un bloque, este es
        // precisamente el bloque que se reemplazará.
        // No debe compararse consigo mismo.
        if (asignatura.id == asignaturaId &&
            bloqueIndexIgnorar != null &&
            index == bloqueIndexIgnorar) {
          continue;
        }

        // Los bloques solamente pueden chocar
        // si pertenecen al mismo día.
        if (bloqueExistente.dia != bloquePropuesto.dia) {
          continue;
        }

        final int? inicioExistente = _horaAMinutos(bloqueExistente.horaInicio);

        final int? finExistente = _horaAMinutos(bloqueExistente.horaFin);

        if (inicioExistente == null ||
            finExistente == null ||
            finExistente <= inicioExistente) {
          continue;
        }

        // Dos intervalos se superponen cuando:
        //
        // inicioNuevo < finExistente
        // &&
        // finNuevo > inicioExistente
        //
        // Por ejemplo:
        //
        // Lenguaje 08:00 - 09:30
        // Historia 09:00 - 10:00
        //
        // -> conflicto.
        //
        // En cambio:
        //
        // Lenguaje 08:00 - 09:30
        // Historia 09:30 - 10:30
        //
        // -> permitido.
        final bool seSuperponen =
            inicioPropuesto < finExistente && finPropuesto > inicioExistente;

        if (!seSuperponen) {
          continue;
        }

        conflictos.add(
          ConflictoHorario(
            asignatura: asignatura,
            bloque: bloqueExistente,
            bloqueIndex: index,
          ),
        );
      }
    }

    conflictos.sort((a, b) {
      final int inicioA = _horaAMinutos(a.bloque.horaInicio) ?? 0;

      final int inicioB = _horaAMinutos(b.bloque.horaInicio) ?? 0;

      return inicioA.compareTo(inicioB);
    });

    return conflictos;
  }

  // =========================================================
  // HORA -> MINUTOS
  // =========================================================

  int? _horaAMinutos(String hora) {
    final List<String> partes = hora.split(':');

    if (partes.length != 2) {
      return null;
    }

    final int? horas = int.tryParse(partes[0]);
    final int? minutos = int.tryParse(partes[1]);

    if (horas == null ||
        minutos == null ||
        horas < 0 ||
        horas > 23 ||
        minutos < 0 ||
        minutos > 59) {
      return null;
    }

    return (horas * 60) + minutos;
  }
}
