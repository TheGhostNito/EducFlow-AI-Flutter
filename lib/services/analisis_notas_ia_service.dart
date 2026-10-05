import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/nota.dart';

class ResolucionAnalisisNotasIa {
  const ResolucionAnalisisNotasIa({
    required this.asignaturas,
    required this.notasHipoteticas,
    required this.advertencias,
  });

  final List<Asignatura> asignaturas;
  final Map<String, double> notasHipoteticas;
  final List<Map<String, Object?>> advertencias;
}

class AnalisisNotasIaService {
  const AnalisisNotasIaService();

  ResolucionAnalisisNotasIa resolver({
    required Map<String, Object?> argumentos,
    required List<Asignatura> asignaturas,
    required List<Evaluacion> evaluaciones,
    required Map<String, CalificacionEvaluacion> calificaciones,
    required ConfiguracionNotas configuracion,
  }) {
    final advertencias = <Map<String, Object?>>[];
    final consultaAsignatura =
        argumentos['asignatura']?.toString().trim() ?? '';
    List<Asignatura> seleccionadas = asignaturas;

    if (consultaAsignatura.isNotEmpty) {
      final coincidencias = _buscarAsignaturas(consultaAsignatura, asignaturas);
      if (coincidencias.length == 1) {
        seleccionadas = coincidencias;
      } else {
        seleccionadas = const [];
        advertencias.add({
          'codigo': coincidencias.isEmpty
              ? 'asignatura_no_encontrada'
              : 'asignatura_ambigua',
          'consulta': consultaAsignatura,
          'coincidencias': coincidencias.map((item) => item.nombre).toList(),
        });
      }
    }

    final idsAsignaturas = seleccionadas.map((item) => item.id).toSet();
    final candidatas = evaluaciones
        .where((item) => idsAsignaturas.contains(item.asignaturaId))
        .toList();
    final hipoteticas = <String, double>{};
    final escenarios = argumentos['escenarios'];

    if (escenarios != null && escenarios is! List) {
      advertencias.add({'codigo': 'escenarios_formato_invalido'});
    } else if (escenarios is List) {
      for (final escenario in escenarios) {
        if (escenario is! Map) {
          advertencias.add({'codigo': 'escenario_formato_invalido'});
          continue;
        }
        final nombre = escenario['evaluacion']?.toString().trim() ?? '';
        final nota = _numero(escenario['nota']);
        if (nombre.isEmpty ||
            nota == null ||
            !nota.isFinite ||
            nota < configuracion.notaMinima ||
            nota > configuracion.notaMaxima) {
          advertencias.add({
            'codigo': 'escenario_invalido',
            'evaluacion': nombre,
            'nota': nota,
          });
          continue;
        }

        final coincidencias = _buscarEvaluaciones(nombre, candidatas);
        if (coincidencias.length != 1) {
          advertencias.add({
            'codigo': coincidencias.isEmpty
                ? 'evaluacion_no_encontrada'
                : 'evaluacion_ambigua',
            'consulta': nombre,
            'coincidencias': coincidencias.map((item) => item.titulo).toList(),
          });
          continue;
        }
        final evaluacion = coincidencias.single;
        if (calificaciones.containsKey(evaluacion.id)) {
          advertencias.add({
            'codigo': 'evaluacion_ya_calificada',
            'evaluacion': evaluacion.titulo,
          });
          continue;
        }
        hipoteticas[evaluacion.id] = nota;
      }
    }

    return ResolucionAnalisisNotasIa(
      asignaturas: List.unmodifiable(seleccionadas),
      notasHipoteticas: Map.unmodifiable(hipoteticas),
      advertencias: List.unmodifiable(advertencias),
    );
  }

  List<Asignatura> _buscarAsignaturas(
    String consulta,
    List<Asignatura> asignaturas,
  ) {
    final normalizada = _normalizar(consulta);
    final exactas = asignaturas.where((item) {
      return _normalizar(item.nombre) == normalizada ||
          _normalizar(item.sigla ?? '') == normalizada;
    }).toList();
    if (exactas.isNotEmpty) return exactas;
    return asignaturas.where((item) {
      final nombre = _normalizar(item.nombre);
      final sigla = _normalizar(item.sigla ?? '');
      return nombre.contains(normalizada) ||
          (sigla.isNotEmpty && sigla.contains(normalizada));
    }).toList();
  }

  List<Evaluacion> _buscarEvaluaciones(
    String consulta,
    List<Evaluacion> evaluaciones,
  ) {
    final normalizada = _normalizar(consulta);
    final exactas = evaluaciones
        .where((item) => _normalizar(item.titulo) == normalizada)
        .toList();
    if (exactas.isNotEmpty) return exactas;
    return evaluaciones
        .where((item) => _normalizar(item.titulo).contains(normalizada))
        .toList();
  }

  String _normalizar(String value) {
    const reemplazos = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'ü': 'u',
      'ñ': 'n',
    };
    var resultado = value.toLowerCase().trim();
    reemplazos.forEach((origen, destino) {
      resultado = resultado.replaceAll(origen, destino);
    });
    return resultado.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  double? _numero(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
  }
}
