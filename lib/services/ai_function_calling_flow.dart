import 'dart:async';

typedef AiDiagnosticLogger = void Function(
  String event,
  Map<String, Object?> details,
);

class AiToolCallRequest {
  const AiToolCallRequest({
    required this.name,
    required this.arguments,
    this.id,
  });

  final String name;
  final Map<String, Object?> arguments;
  final String? id;
}

class AiToolCallResult {
  const AiToolCallResult({required this.name, required this.result, this.id});

  final String name;
  final Map<String, Object?> result;
  final String? id;
}

class AiModelTurn {
  const AiModelTurn({this.text, this.functionCalls = const []});

  final String? text;
  final List<AiToolCallRequest> functionCalls;
}

class AiRequestTimeoutException implements Exception {
  const AiRequestTimeoutException({required this.timeout, required this.stage});

  final Duration timeout;
  final String stage;

  @override
  String toString() =>
      'La consulta de IA superó ${timeout.inSeconds} segundos en $stage.';
}

class AiToolRoundsExceededException implements Exception {
  const AiToolRoundsExceededException(this.maxRounds);

  final int maxRounds;

  @override
  String toString() =>
      'La IA superó el máximo de $maxRounds rondas de herramientas.';
}

class AiFunctionCallingFlow {
  const AiFunctionCallingFlow({
    this.timeout = defaultTimeout,
    this.maxToolRounds = defaultMaxToolRounds,
    this.logger,
  });

  static const Duration defaultTimeout = Duration(seconds: 45);
  static const int defaultMaxToolRounds = 8;

  final Duration timeout;
  final int maxToolRounds;
  final AiDiagnosticLogger? logger;

  Future<String> run({
    required Future<AiModelTurn> Function() sendInitialMessage,
    required Future<AiModelTurn> Function(List<AiToolCallResult> results)
    sendToolResults,
    required Future<Map<String, Object?>> Function(AiToolCallRequest call)
    executeTool,
  }) {
    var stage = 'envio_prompt';
    final startedAt = DateTime.now();

    Future<String> execute() async {
      _log('request_started', {'stage': stage});
      var response = await sendInitialMessage();
      _log('model_response_received', {
        'stage': stage,
        'functionCalls': response.functionCalls.length,
        'hasText': response.text?.trim().isNotEmpty == true,
      });

      for (var round = 0; round < maxToolRounds; round++) {
        final calls = response.functionCalls;
        if (calls.isEmpty) {
          final text = response.text?.trim() ?? '';
          if (text.isEmpty) {
            throw StateError('Gemini no devolvió una respuesta de texto.');
          }
          _log('request_completed', {
            'rounds': round,
            'responseCharacters': text.length,
            'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
          });
          return text;
        }

        final toolResults = <AiToolCallResult>[];
        for (final call in calls) {
          stage = 'herramienta:${call.name}';
          _log('function_call_received', {
            'round': round + 1,
            'name': call.name,
            'arguments': call.arguments,
          });

          Map<String, Object?> result;
          try {
            result = await executeTool(call);
            _log('tool_completed', {
              'round': round + 1,
              'name': call.name,
              'success': result['exito'],
              'resultKeys': result.keys.toList(growable: false),
            });
          } catch (error) {
            result = const {
              'exito': false,
              'error': 'La herramienta no estuvo disponible. No inventes resultados.',
            };
            _log('tool_failed', {
              'round': round + 1,
              'name': call.name,
              'errorType': error.runtimeType.toString(),
            });
          }

          toolResults.add(
            AiToolCallResult(name: call.name, result: result, id: call.id),
          );
        }

        stage = 'retorno_herramientas_a_gemini';
        _log('tool_results_sent', {
          'round': round + 1,
          'tools': toolResults.map((item) => item.name).toList(growable: false),
        });
        response = await sendToolResults(toolResults);
        _log('model_response_received', {
          'stage': stage,
          'round': round + 1,
          'functionCalls': response.functionCalls.length,
          'hasText': response.text?.trim().isNotEmpty == true,
        });
      }

      throw AiToolRoundsExceededException(maxToolRounds);
    }

    Future<String> guardedExecution() async {
      try {
        return await execute().timeout(
          timeout,
          onTimeout: () {
            _log('request_timeout', {
              'stage': stage,
              'timeoutSeconds': timeout.inSeconds,
            });
            throw AiRequestTimeoutException(timeout: timeout, stage: stage);
          },
        );
      } on AiRequestTimeoutException {
        rethrow;
      } catch (error) {
        _log('request_failed', {
          'stage': stage,
          'errorType': error.runtimeType.toString(),
        });
        rethrow;
      }
    }

    return guardedExecution();
  }

  void _log(String event, Map<String, Object?> details) {
    logger?.call(event, details);
  }
}
