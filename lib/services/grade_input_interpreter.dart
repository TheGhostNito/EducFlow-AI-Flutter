import 'dart:math' as math;

import '../models/nota.dart';

enum EstadoInterpretacionNota { valida, vacia, invalida, ambigua }

class ResultadoInterpretacionNota {
  const ResultadoInterpretacionNota(this.estado, [this.valor]);

  final EstadoInterpretacionNota estado;
  final double? valor;

  bool get esValida => estado == EstadoInterpretacionNota.valida;
}

class GradeInputInterpreter {
  const GradeInputInterpreter();

  ResultadoInterpretacionNota interpretar(
    String input,
    ConfiguracionNotas configuracion,
  ) {
    final text = input.trim();
    if (text.isEmpty) {
      return const ResultadoInterpretacionNota(EstadoInterpretacionNota.vacia);
    }
    if (!configuracion.esValida ||
        !RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(text)) {
      return const ResultadoInterpretacionNota(
        EstadoInterpretacionNota.invalida,
      );
    }

    if (text.contains(',') || text.contains('.')) {
      final value = double.tryParse(text.replaceAll(',', '.'));
      return _validar(value, configuracion);
    }

    final integer = int.tryParse(text);
    if (integer == null) {
      return const ResultadoInterpretacionNota(
        EstadoInterpretacionNota.invalida,
      );
    }

    final candidates = <double>{};
    final direct = integer.toDouble();
    if (_dentro(direct, configuracion)) candidates.add(direct);

    if (configuracion.decimales > 0 && text.length > 1) {
      final implied = integer / math.pow(10, configuracion.decimales);
      if (_dentro(implied, configuracion)) candidates.add(implied);
    }

    if (candidates.isEmpty) {
      return const ResultadoInterpretacionNota(
        EstadoInterpretacionNota.invalida,
      );
    }
    if (candidates.length > 1) {
      return const ResultadoInterpretacionNota(
        EstadoInterpretacionNota.ambigua,
      );
    }
    return ResultadoInterpretacionNota(
      EstadoInterpretacionNota.valida,
      candidates.single,
    );
  }

  ResultadoInterpretacionNota _validar(
    double? value,
    ConfiguracionNotas configuration,
  ) {
    if (value == null || !value.isFinite || !_dentro(value, configuration)) {
      return const ResultadoInterpretacionNota(
        EstadoInterpretacionNota.invalida,
      );
    }
    return ResultadoInterpretacionNota(EstadoInterpretacionNota.valida, value);
  }

  bool _dentro(double value, ConfiguracionNotas configuration) {
    return value >= configuration.notaMinima &&
        value <= configuration.notaMaxima;
  }
}
