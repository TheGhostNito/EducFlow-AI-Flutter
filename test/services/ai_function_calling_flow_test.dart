import 'dart:async';

import 'package:eduflow_ai/models/nota.dart';
import 'package:eduflow_ai/services/ai_function_calling_flow.dart';
import 'package:eduflow_ai/services/calculo_notas_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analizarNotas completa el caso Big Data y vuelve a Gemini', () async {
    const calculator = CalculoNotasService();
    var toolCalls = 0;
    var resultTurns = 0;
    final flow = AiFunctionCallingFlow(timeout: const Duration(seconds: 1));

    final response = await flow.run(
      sendInitialMessage: () async => const AiModelTurn(
        functionCalls: [
          AiToolCallRequest(
            name: 'analizarNotas',
            arguments: {'asignatura': 'Big Data'},
            id: 'tool-1',
          ),
        ],
      ),
      executeTool: (call) async {
        toolCalls++;
        expect(call.name, 'analizarNotas');
        expect(call.arguments['asignatura'], 'Big Data');
        final result = calculator.calcular(
          evaluaciones: const [
            EntradaCalculoNota(
              id: 'presentacion',
              nombre: 'Presentación',
              ponderacion: 100,
              notaReal: 5.8,
            ),
            EntradaCalculoNota(id: 'examen', nombre: 'Examen', ponderacion: 0),
          ],
          configuracion: ConfiguracionNotas.predeterminada,
          objetivo: 4,
          configuracionAsignatura: const ConfiguracionCalculoAsignatura(
            asignaturaId: 'big-data',
            esquema: EsquemaCalculoNotas.presentacionExamen,
            pesoPresentacion: 60,
            pesoExamen: 40,
            evaluacionExamenId: 'examen',
          ),
        );
        return {
          'exito': true,
          'asignatura': 'Big Data',
          ...result.toStructuredMap(),
        };
      },
      sendToolResults: (results) async {
        resultTurns++;
        expect(results, hasLength(1));
        expect(results.single.name, 'analizarNotas');
        expect(
          results.single.result['notaNecesariaExamen'],
          closeTo(1.3, 1e-9),
        );
        return const AiModelTurn(
          text: 'Necesitas un 1,3 en el examen para terminar con 4,0.',
        );
      },
    );

    expect(toolCalls, 1);
    expect(resultTurns, 1);
    expect(response, contains('1,3'));
  });

  test('propaga un error remoto y termina el request', () async {
    final events = <String>[];
    final flow = AiFunctionCallingFlow(
      timeout: const Duration(seconds: 1),
      logger: (event, _) => events.add(event),
    );

    await expectLater(
      flow.run(
        sendInitialMessage: () => Future<AiModelTurn>.error(
          StateError('servicio remoto no disponible'),
        ),
        executeTool: (_) async => const {},
        sendToolResults: (_) async => const AiModelTurn(text: 'sin uso'),
      ),
      throwsStateError,
    );
    expect(events, contains('request_failed'));
  });

  test('timeout identifica la etapa y no queda esperando', () async {
    final pending = Completer<AiModelTurn>();
    const flow = AiFunctionCallingFlow(timeout: Duration(milliseconds: 20));

    await expectLater(
      flow.run(
        sendInitialMessage: () => pending.future,
        executeTool: (_) async => const {},
        sendToolResults: (_) async => const AiModelTurn(text: 'sin uso'),
      ),
      throwsA(
        isA<AiRequestTimeoutException>().having(
          (error) => error.stage,
          'stage',
          'envio_prompt',
        ),
      ),
    );
  });

  test('error de herramienta vuelve estructurado a Gemini', () async {
    const flow = AiFunctionCallingFlow(timeout: Duration(seconds: 1));

    final response = await flow.run(
      sendInitialMessage: () async => const AiModelTurn(
        functionCalls: [
          AiToolCallRequest(
            name: 'analizarNotas',
            arguments: {'asignatura': 'Big Data'},
          ),
        ],
      ),
      executeTool: (_) =>
          Future<Map<String, Object?>>.error(StateError('falló Supabase')),
      sendToolResults: (results) async {
        expect(results.single.result['exito'], isFalse);
        expect(results.single.result['error'], contains('No inventes'));
        return const AiModelTurn(
          text: 'No pude consultar tus notas. Inténtalo nuevamente.',
        );
      },
    );

    expect(response, contains('Inténtalo'));
  });

  test('máximo de rondas evita un loop infinito', () async {
    const call = AiToolCallRequest(
      name: 'analizarNotas',
      arguments: {'asignatura': 'Big Data'},
    );
    const flow = AiFunctionCallingFlow(
      timeout: Duration(seconds: 1),
      maxToolRounds: 3,
    );
    var returnsToModel = 0;

    await expectLater(
      flow.run(
        sendInitialMessage: () async =>
            const AiModelTurn(functionCalls: [call]),
        executeTool: (_) async => const {'exito': true},
        sendToolResults: (_) async {
          returnsToModel++;
          return const AiModelTurn(functionCalls: [call]);
        },
      ),
      throwsA(
        isA<AiToolRoundsExceededException>().having(
          (error) => error.maxRounds,
          'maxRounds',
          3,
        ),
      ),
    );
    expect(returnsToModel, 3);
  });
}
