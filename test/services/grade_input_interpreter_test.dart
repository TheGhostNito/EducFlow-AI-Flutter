import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/services/grade_input_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interpreter = GradeInputInterpreter();
  const chile = ConfiguracionNotas.predeterminada;

  for (final entry in {'65': 6.5, '58': 5.8, '40': 4.0, '55': 5.5}.entries) {
    test('${entry.key} se interpreta como ${entry.value}', () {
      final result = interpreter.interpretar(entry.key, chile);
      expect(result.estado, EstadoInterpretacionNota.valida);
      expect(result.valor, entry.value);
    });
  }

  test('acepta entero, coma y punto explícitos', () {
    expect(interpreter.interpretar('7', chile).valor, 7);
    expect(interpreter.interpretar('6,5', chile).valor, 6.5);
    expect(interpreter.interpretar('6.5', chile).valor, 6.5);
  });

  test('rechaza formatos y valores fuera de la escala', () {
    expect(
      interpreter.interpretar('6,5,2', chile).estado,
      EstadoInterpretacionNota.invalida,
    );
    expect(
      interpreter.interpretar('99', chile).estado,
      EstadoInterpretacionNota.invalida,
    );
  });

  test('no inventa una conversión cuando la escala hace 65 ambiguo', () {
    const percentage = ConfiguracionNotas(
      notaMinima: 0,
      notaMaxima: 100,
      notaAprobacion: 60,
      decimales: 1,
      politicaRedondeo: PoliticaRedondeoNotas.masCercano,
    );
    expect(
      interpreter.interpretar('65', percentage).estado,
      EstadoInterpretacionNota.ambigua,
    );
  });

  test('respeta una escala sin decimales', () {
    const percentage = ConfiguracionNotas(
      notaMinima: 0,
      notaMaxima: 100,
      notaAprobacion: 60,
      decimales: 0,
      politicaRedondeo: PoliticaRedondeoNotas.masCercano,
    );
    expect(interpreter.interpretar('65', percentage).valor, 65);
  });
}
