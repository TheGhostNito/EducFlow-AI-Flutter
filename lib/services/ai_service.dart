import 'dart:convert';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/nota.dart';
import '../models/periodo_academico.dart';
import '../models/plan_estudio.dart';
import '../models/perfil_usuario.dart';
import '../models/sesion_clase.dart';
import '../models/ai_conversation.dart';
import '../models/tarea.dart';
import 'asignaturas_service.dart';
import 'ai_deterministic_query_service.dart';
import 'ai_conversation_context.dart';
import 'ai_failure_diagnostics.dart';
import 'ai_function_calling_flow.dart';
import 'ai_schedule_context_builder.dart';
import 'analisis_notas_ia_service.dart';
import 'calculo_notas_service.dart';
import 'evaluaciones_service.dart';
import 'notas_service.dart';
import 'perfil_service.dart';
import 'periodos_academicos_service.dart';
import 'plan_estudio_proposal_builder.dart';
import 'sesiones_clase_service.dart';
import 'tareas_service.dart';

abstract interface class AiAssistantClient {
  void iniciarNuevoChat();

  void iniciarConversacion({
    required String conversationId,
    List<AiChatMessage> history = const [],
  });

  Future<String> enviarMensaje(
    String mensaje, {
    required List<AiChatMessage> history,
  });
}

abstract interface class AiStudyPlanProposalSource {
  PlanEstudioPropuesto? tomarUltimaPropuestaPlanEstudio();

  void descartarPlanEstudio(String planId);
}

class AiService implements AiAssistantClient, AiStudyPlanProposalSource {
  AiService._();

  static final AiService instance = AiService._();
  static const String modelName = 'gemini-3.5-flash';
  static const double modelTemperature = 0.35;
  static const int modelMaxOutputTokens = 4096;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PerfilService _perfilService = PerfilService();
  final AsignaturasService _asignaturasService = AsignaturasService.instance;
  final TareasService _tareasService = TareasService.instance;
  final EvaluacionesService _evaluacionesService = EvaluacionesService.instance;
  final PeriodosAcademicosService _periodosService =
      PeriodosAcademicosService();
  final SesionesClaseService _sesionesClaseService = SesionesClaseService();
  final NotasService _notasService = NotasService.instance;
  final CalculoNotasService _calculoNotasService = const CalculoNotasService();
  final AnalisisNotasIaService _analisisNotasIaService =
      const AnalisisNotasIaService();
  final PlanEstudioProposalBuilder _planEstudioBuilder =
      const PlanEstudioProposalBuilder();
  final AiScheduleContextBuilder _scheduleContextBuilder =
      const AiScheduleContextBuilder();
  late final AiFunctionCallingFlow _functionCallingFlow = AiFunctionCallingFlow(
    logger: _registrarDiagnostico,
  );
  late final AiDeterministicQueryService _deterministicQueryService =
      AiDeterministicQueryService(
        loadSubjects: _asignaturasService.obtenerTodas,
        loadEvaluations: _evaluacionesService.obtenerTodas,
        loadTasks: _tareasService.obtenerTodas,
        logger: _registrarDiagnostico,
      );

  String? _chatUid;
  String? _conversationId;
  List<AiChatMessage> _loadedHistory = const [];
  PlanEstudioPropuesto? _planEstudioActual;
  PlanEstudioPropuesto? _ultimaPropuestaPlanEstudio;
  final Set<String> _toolsConsultedThisRequest = {};

  late final GenerativeModel _model = FirebaseAI.googleAI().generativeModel(
    model: modelName,
    generationConfig: GenerationConfig(
      temperature: modelTemperature,
      maxOutputTokens: modelMaxOutputTokens,
    ),
    systemInstruction: Content.system('''
Eres EducFlow AI, el asistente académico inteligente de la aplicación EducFlow AI.

Tu objetivo es ayudar al usuario a entender y organizar su información académica de forma clara, natural y útil.

REGLAS IMPORTANTES:
- Responde en el mismo idioma en que te escriba el usuario, salvo que te pida otro.
- No inventes información académica.
- Cuando una pregunta dependa de datos reales de EducFlow, usa las herramientas disponibles.
- Los datos devueltos por las herramientas son la fuente de verdad.
- Un resultado con exito false indica un error de consulta, no ausencia de datos. En ese caso informa que no fue posible consultar el contexto y no digas que el usuario carece de horarios, tareas, evaluaciones o asignaturas.
- Solo interpreta que no existe horario cuando obtenerHorario responde exito true y sinDatos true.
- Para notas, promedios, objetivos y proyecciones usa siempre analizarNotas. No recalcules ni inventes resultados: interpreta el resultado determinista que entrega esa herramienta.
- Puedes usar varias herramientas para una misma respuesta.
- Si un dato no está disponible, dilo claramente.
- Para referencias como hoy, mañana, esta semana, pendientes o próximas evaluaciones, usa la fecha actual devuelta por las herramientas.
- Las herramientas académicas son de lectura. proponerPlanEstudio solo crea o reemplaza una propuesta local: nunca guarda actividades por sí misma.
- Para un plan de estudio consulta asignaturas y, cuando corresponda, evaluaciones, tareas y horario antes de proponerlo. Si falta la asignatura, la fecha objetivo o una preferencia indispensable, pregunta antes de crear la propuesta.
- Toda propuesta debe respetar clases, evaluaciones, tareas y otras sesiones conocidas. No inventes disponibilidad ni fechas académicas.
- Para crear o modificar un plan usa proponerPlanEstudio y entrega siempre la propuesta completa actualizada. Las sesiones inequívocas usan fechas YYYY-MM-DD, horas HH:mm y duraciones razonables.
- Después de proponer o modificar, explica que el plan aún no está guardado y que el estudiante debe revisarlo y confirmarlo mediante la acción Guardar del chat.
- Cuando proponerPlanEstudio tenga éxito, responde con una introducción breve y útil. No vuelvas a enumerar sesiones, fechas, horarios ni actividades: la tarjeta estructurada es la representación principal del plan.
- No afirmes que una propuesta quedó en el Calendario: la aplicación confirma el guardado solo después de que Supabase responde correctamente.
- Para otras modificaciones de datos que no sean propuestas de planes, explica que esa escritura todavía no está disponible.
- No muestres IDs internos salvo que sea estrictamente necesario.
'''),
    tools: [
      Tool.functionDeclarations([
        FunctionDeclaration(
          'obtenerPerfil',
          'Obtiene el perfil académico real del usuario autenticado: nombre, nivel educativo, establecimiento, curso, carrera, semestre, año de ingreso, sede, jornada y estado académico.',
          parameters: const {},
        ),
        FunctionDeclaration(
          'obtenerAsignaturas',
          'Obtiene todas las asignaturas reales del usuario, incluyendo profesor, sala, periodo, estado, sigla, sección, créditos y otros datos académicos.',
          parameters: const {},
        ),
        FunctionDeclaration(
          'obtenerHorario',
          'Obtiene todos los bloques semanales reales del usuario. Úsala para clases de hoy o mañana, horarios, entradas, salidas, profesores y salas.',
          parameters: const {},
        ),
        FunctionDeclaration(
          'obtenerTareas',
          'Obtiene las tareas reales del usuario, incluyendo pendientes y completadas, prioridad, asignatura, fecha y hora de entrega.',
          parameters: const {},
        ),
        FunctionDeclaration(
          'obtenerEvaluaciones',
          'Obtiene las evaluaciones reales del usuario, incluyendo asignatura, tipo, fecha, hora, descripción y ponderación.',
          parameters: const {},
        ),
        FunctionDeclaration(
          'proponerPlanEstudio',
          'Crea o reemplaza la propuesta local de plan de estudio que el estudiante debe revisar antes de guardar. Úsala solo después de resolver asignatura, fecha objetivo, disponibilidad y conflictos con las herramientas de lectura.',
          parameters: {
            'titulo': Schema.string(
              description: 'Título breve y legible del plan.',
            ),
            'objetivo': Schema.string(
              description: 'Objetivo académico concreto del plan.',
            ),
            'asignaturaId': Schema.string(
              description: 'ID exacto devuelto por obtenerAsignaturas.',
            ),
            'asignatura': Schema.string(
              description: 'Nombre o sigla exactos de la asignatura.',
            ),
            'evaluacionId': Schema.string(
              description: 'ID de la evaluación que origina el plan.',
            ),
            'sesiones': Schema.array(
              description: 'Propuesta completa, incluyendo las sesiones conservadas al modificarla.',
              items: Schema.object(
                properties: {
                  'titulo': Schema.string(),
                  'actividad': Schema.string(),
                  'fecha': Schema.string(
                    description: 'Fecha local exacta YYYY-MM-DD.',
                  ),
                  'horaInicio': Schema.string(
                    description: 'Hora local exacta HH:mm.',
                  ),
                  'duracionMinutos': Schema.integer(
                    description: 'Duración entre 15 y 240 minutos.',
                  ),
                },
              ),
            ),
          },
          optionalParameters: const ['evaluacionId'],
        ),
        FunctionDeclaration(
          'analizarNotas',
          'Obtiene el análisis determinista de notas, incluyendo esquemas directos o presentación más examen final. Puede filtrar una asignatura y simular notas hipotéticas sin guardarlas. Úsala para cualquier pregunta sobre promedios, aprobación, objetivos o escenarios.',
          parameters: {
            'asignatura': Schema.string(
              description: 'Nombre o sigla de la asignatura. Omítelo para analizar todas.',
            ),
            'escenarios': Schema.array(
              description: 'Notas hipotéticas que solo se usan en este cálculo y nunca se guardan.',
              items: Schema.object(
                properties: {
                  'evaluacion': Schema.string(
                    description: 'Nombre de una evaluación pendiente.',
                  ),
                  'nota': Schema.number(
                    description:
                        'Nota hipotética dentro de la escala configurada.',
                  ),
                },
              ),
            ),
            'notaPresentacionHipotetica': Schema.number(
              description: 'Nota de presentación hipotética para una asignatura con esquema presentación más examen.',
            ),
            'notaExamenHipotetica': Schema.number(
              description: 'Nota de examen hipotética para una asignatura con examen final configurado.',
            ),
            'objetivoPresentacion': Schema.number(
              description: 'Nota de presentación que el usuario quiere alcanzar antes del examen.',
            ),
          },
          optionalParameters: const [
            'asignatura',
            'escenarios',
            'notaPresentacionHipotetica',
            'notaExamenHipotetica',
            'objetivoPresentacion',
          ],
        ),
      ]),
    ],
    toolConfig: ToolConfig(functionCallingConfig: FunctionCallingConfig.auto()),
  );

  @override
  void iniciarNuevoChat() {
    _chatUid = null;
    _conversationId = null;
    _loadedHistory = const [];
    _planEstudioActual = null;
    _ultimaPropuestaPlanEstudio = null;
    _toolsConsultedThisRequest.clear();
  }

  @override
  void iniciarConversacion({
    required String conversationId,
    List<AiChatMessage> history = const [],
  }) {
    assert(conversationId.isNotEmpty);
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('No existe un usuario autenticado.');
    }

    if (_conversationId != conversationId || _chatUid != user.uid) {
      _planEstudioActual = null;
      _ultimaPropuestaPlanEstudio = null;
    }
    _chatUid = user.uid;
    _conversationId = conversationId;
    _loadedHistory = List<AiChatMessage>.of(history);
  }

  List<Content> _buildModelHistory(
    List<AiChatMessage> messages,
    String currentMessage,
  ) {
    return AiConversationContext.completedHistory(
      messages,
      currentMessage: currentMessage,
    ).map((message) {
      if (message.role == AiChatRole.user) {
        return Content.text(message.text);
      }

      return Content.model([TextPart(message.text)]);
    }).toList();
  }

  @override
  Future<String> enviarMensaje(
    String mensaje, {
    required List<AiChatMessage> history,
  }) async {
    final String texto = mensaje.trim();

    if (texto.isEmpty) {
      throw ArgumentError('El mensaje no puede estar vacío.');
    }

    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('No existe un usuario autenticado.');
    }
    if (_chatUid != user.uid || _conversationId == null) {
      throw StateError(
        'La conversación activa no pertenece al usuario actual.',
      );
    }

    _ultimaPropuestaPlanEstudio = null;
    final Stopwatch requestStopwatch = Stopwatch()..start();
    final String? deterministic = _planEstudioActual == null
        ? await _deterministicQueryService.tryResolve(texto)
        : null;
    if (deterministic != null) {
      requestStopwatch.stop();
      _registrarDiagnostico('assistant_request_completed', {
        'route': 'deterministic',
        'elapsedMs': requestStopwatch.elapsedMilliseconds,
      });
      return deterministic;
    }

    _registrarDiagnostico('assistant_route_selected', {'route': 'gemini'});
    final textoModelo = _mensajeConPlanActual(texto);
    final ChatSession chat = _model.startChat(
      history: _buildModelHistory(
        history.isEmpty ? _loadedHistory : history,
        texto,
      ),
      maxTurns: 40,
    );
    try {
      final String response = await _functionCallingFlow.run(
        sendInitialMessage: () async {
          final response = await chat.sendMessage(Content.text(textoModelo));
          return _convertirTurno(response);
        },
        executeTool: (call) => _ejecutarHerramienta(call.name, call.arguments),
        sendToolResults: (results) async {
          final responses = results
              .map(
                (item) => FunctionResponse(item.name, item.result, id: item.id),
              )
              .toList(growable: false);

          // Firebase AI Logic con Gemini Developer API acepta las respuestas
          // de herramientas como turno USER. El rol "function" es rechazado
          // por el backend utilizado actualmente.
          final response = await chat.sendMessage(Content('user', responses));
          return _convertirTurno(response);
        },
      );
      requestStopwatch.stop();
      _registrarDiagnostico('assistant_request_completed', {
        'route': 'gemini',
        'elapsedMs': requestStopwatch.elapsedMilliseconds,
      });
      return response;
    } catch (error) {
      requestStopwatch.stop();
      final AiFailureDiagnostics diagnostics = AiFailureDiagnostics.from(error);
      _registrarDiagnostico('assistant_request_failed', {
        'route': 'gemini',
        'model': modelName,
        'provider': 'geminiDeveloperApi',
        'elapsedMs': requestStopwatch.elapsedMilliseconds,
        ...diagnostics.toSafeLog(),
      });
      // Cada solicitud reconstruye una sesión desde el historial confirmado.
      // Una operación fallida no contamina el siguiente turno ni se reenvía.
      rethrow;
    }
  }

  AiModelTurn _convertirTurno(GenerateContentResponse response) {
    return AiModelTurn(
      text: response.text,
      functionCalls: response.functionCalls
          .map(
            (call) => AiToolCallRequest(
              name: call.name,
              arguments: call.args,
              id: call.id,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<Map<String, Object?>> _ejecutarHerramienta(
    String nombre,
    Map<String, Object?> argumentos,
  ) async {
    final Map<String, Object?> result;
    switch (nombre) {
      case 'obtenerPerfil':
        result = await _obtenerPerfil();
        break;
      case 'obtenerAsignaturas':
        result = await _obtenerAsignaturas();
        break;
      case 'obtenerHorario':
        result = await _obtenerHorario();
        break;
      case 'obtenerTareas':
        result = await _obtenerTareas();
        break;
      case 'obtenerEvaluaciones':
        result = await _obtenerEvaluaciones();
        break;
      case 'proponerPlanEstudio':
        result = await _proponerPlanEstudio(argumentos);
        break;
      case 'analizarNotas':
        result = await _obtenerAnalisisNotas(argumentos);
        break;
      default:
        result = {
          'exito': false,
          'error': 'Herramienta no implementada: $nombre',
        };
        break;
    }
    if (result['exito'] != false) {
      _toolsConsultedThisRequest.add(nombre);
    }
    return result;
  }

  Future<Map<String, Object?>> _obtenerPerfil() async {
    final User user = _usuarioActual();
    final PerfilUsuario? perfil = await _perfilService.obtenerPerfil(user.uid);

    if (perfil == null) {
      return {
        'exito': false,
        'mensaje': 'El usuario todavía no tiene un perfil disponible.',
        'fechaActual': _fechaActual(),
      };
    }

    return {
      'exito': true,
      'fechaActual': _fechaActual(),
      'perfil': {
        'nombre': perfil.nombre,
        'nivelEducativo': perfil.nivelEducativo.valorFirestore,
        'nombreEstablecimiento': perfil.nombreEstablecimiento,
        'tipoEstablecimiento': perfil.tipoEstablecimiento,
        'cursoActual': perfil.cursoActual,
        'carrera': perfil.carrera,
        'semestreActual': perfil.semestreActual,
        'anioIngreso': perfil.anioIngreso,
        'sede': perfil.sede,
        'jornada': perfil.jornada,
        'estadoAcademico': perfil.estadoAcademico,
        'idioma': perfil.idioma,
        'perfilCompleto': perfil.perfilCompleto,
      },
    };
  }

  Future<Map<String, Object?>> _obtenerAsignaturas() async {
    final List<Asignatura> asignaturas = await _asignaturasService
        .obtenerTodas();

    return {
      'exito': true,
      'fechaActual': _fechaActual(),
      'cantidad': asignaturas.length,
      'asignaturas': asignaturas.map((asignatura) {
        return {
          'id': asignatura.id,
          'nombre': asignatura.nombre,
          'profesor': _nullable(asignatura.profesor),
          'sala': _nullable(asignatura.sala),
          'periodo': _nullable(asignatura.periodo),
          'estado': asignatura.estado.valorFirestore,
          'origen': asignatura.origen.valorFirestore,
          'sigla': _nullable(asignatura.sigla),
          'seccion': _nullable(asignatura.seccion),
          'creditos': asignatura.creditos,
          'semestreMalla': asignatura.semestreMalla,
          'cursoNivel': _nullable(asignatura.cursoNivel),
          'anioAcademico': asignatura.anioAcademico,
          'modalidad': _nullable(asignatura.modalidad),
          'lugar': _nullable(asignatura.lugar),
          'institucion': _nullable(asignatura.institucion),
        };
      }).toList(),
    };
  }

  Future<Map<String, Object?>> _obtenerHorario() async {
    try {
      final asignaturas = await _asignaturasService.obtenerTodas();
      final tienePeriodos = asignaturas.any(
        (asignatura) =>
            asignatura.periodoAcademicoId?.trim().isNotEmpty == true,
      );
      final List<PeriodoAcademico> periodos;
      final List<SesionClase> sesiones;
      if (tienePeriodos) {
        final complementos = await Future.wait([
          _periodosService.obtenerTodos(),
          _sesionesClaseService.obtenerTodas(),
        ]);
        periodos = complementos[0] as List<PeriodoAcademico>;
        sesiones = complementos[1] as List<SesionClase>;
      } else {
        periodos = const [];
        sesiones = const [];
      }
      return _scheduleContextBuilder.build(
        subjects: asignaturas,
        periods: periodos,
        sessions: sesiones,
        now: DateTime.now(),
      );
    } catch (error) {
      _registrarDiagnostico('obtener_horario_failed', {
        'errorType': error.runtimeType.toString(),
      });
      return {
        'exito': false,
        'estado': 'error_consulta_horario',
        'sinDatos': false,
        'error': 'No fue posible consultar el horario académico. No interpretes este error como ausencia de bloques.',
      };
    }
  }

  Future<Map<String, Object?>> _obtenerTareas() async {
    final List<Tarea> tareas = await _tareasService.obtenerTodas();
    final List<Asignatura> asignaturas = await _asignaturasService
        .obtenerTodas();

    final Map<String, String> nombres = {
      for (final Asignatura asignatura in asignaturas)
        asignatura.id: asignatura.nombre,
    };

    return {
      'exito': true,
      'fechaActual': _fechaActual(),
      'cantidad': tareas.length,
      'pendientes': tareas.where((tarea) => tarea.pendiente).length,
      'completadas': tareas.where((tarea) => tarea.completada).length,
      'tareas': tareas.map((tarea) {
        return {
          'titulo': tarea.titulo,
          'descripcion': _nullable(tarea.descripcion),
          'asignatura': tarea.asignaturaId == null
              ? null
              : nombres[tarea.asignaturaId!],
          'prioridad': tarea.prioridad.valorPersistencia,
          'estado': tarea.estado.valorPersistencia,
          'fechaEntrega': _fechaNullable(tarea.fechaEntrega),
          'horaEntrega': _nullable(tarea.horaEntrega),
          'completadaEn': tarea.completadaEn?.toIso8601String(),
        };
      }).toList(),
    };
  }

  Future<Map<String, Object?>> _obtenerEvaluaciones() async {
    final List<Evaluacion> evaluaciones = await _evaluacionesService
        .obtenerTodas();
    final List<Asignatura> asignaturas = await _asignaturasService
        .obtenerTodas();

    final Map<String, String> nombres = {
      for (final Asignatura asignatura in asignaturas)
        asignatura.id: asignatura.nombre,
    };

    return {
      'exito': true,
      'fechaActual': _fechaActual(),
      'cantidad': evaluaciones.length,
      'evaluaciones': evaluaciones.map((evaluacion) {
        return {
          'id': evaluacion.id,
          'titulo': evaluacion.titulo,
          'asignatura':
              nombres[evaluacion.asignaturaId] ?? 'Asignatura no disponible',
          'tipo': evaluacion.tipo.firestoreValue,
          'fecha': _fecha(evaluacion.fecha),
          'hora': _nullable(evaluacion.hora),
          'descripcion': _nullable(evaluacion.descripcion),
          'ponderacion': evaluacion.ponderacion,
        };
      }).toList(),
    };
  }

  Future<Map<String, Object?>> _proponerPlanEstudio(
    Map<String, Object?> argumentos,
  ) async {
    try {
      const requiredContextTools = {
        'obtenerAsignaturas',
        'obtenerHorario',
        'obtenerTareas',
        'obtenerEvaluaciones',
      };
      final missingTools = requiredContextTools
          .difference(_toolsConsultedThisRequest)
          .toList(growable: false);
      if (missingTools.isNotEmpty) {
        return {
          'exito': false,
          'error': 'Falta consultar contexto académico antes de proponer.',
          'herramientasPendientes': missingTools,
          'instruccion': 'Consulta estas herramientas y luego vuelve a llamar proponerPlanEstudio.',
        };
      }
      final asignaturas = await _asignaturasService.obtenerTodas();
      final conversationId = _conversationId;
      if (conversationId == null) {
        return const {
          'exito': false,
          'error': 'No existe una conversación activa para la propuesta.',
        };
      }
      final propuesta = _planEstudioBuilder.build(
        arguments: argumentos,
        asignaturas: asignaturas,
        conversationId: conversationId,
        now: DateTime.now(),
        current: _planEstudioActual,
      );
      _planEstudioActual = propuesta;
      _ultimaPropuestaPlanEstudio = propuesta;
      return {
        'exito': true,
        'estado': 'propuesta_no_guardada',
        'requiereConfirmacion': true,
        'plan': propuesta.toJson(),
      };
    } on FormatException catch (error) {
      return {
        'exito': false,
        'error': error.message,
        'instruccion': 'Pregunta por el dato faltante o corrige la propuesta sin inventarlo.',
      };
    }
  }

  String _mensajeConPlanActual(String mensaje) {
    final plan = _planEstudioActual;
    if (plan == null) return mensaje;
    return '''
$mensaje

[CONTEXTO INTERNO: PROPUESTA DE PLAN ACTUAL]
${jsonEncode(plan.toJson())}
[FIN DEL CONTEXTO INTERNO]
Si el usuario solicita una modificación del plan, llama nuevamente a proponerPlanEstudio con la propuesta completa actualizada. No afirmes que está guardado.
''';
  }

  @override
  PlanEstudioPropuesto? tomarUltimaPropuestaPlanEstudio() {
    final propuesta = _ultimaPropuestaPlanEstudio;
    _ultimaPropuestaPlanEstudio = null;
    return propuesta;
  }

  @override
  void descartarPlanEstudio(String planId) {
    if (_planEstudioActual?.id == planId) {
      _planEstudioActual = null;
      _ultimaPropuestaPlanEstudio = null;
    }
  }

  Future<Map<String, Object?>> _obtenerAnalisisNotas(
    Map<String, Object?> argumentos,
  ) async {
    _registrarDiagnostico('analizar_notas_started', {
      'argumentKeys': argumentos.keys.toList(growable: false),
    });
    try {
      final datos = await _notasService.obtenerDatos();
      final resolucion = _analisisNotasIaService.resolver(
        argumentos: argumentos,
        asignaturas: datos.asignaturas,
        evaluaciones: datos.evaluaciones,
        calificaciones: datos.calificaciones,
        configuracion: datos.configuracion,
      );

      final analisis = resolucion.asignaturas.map((asignatura) {
        final evaluacionesAsignatura = datos.evaluaciones
            .where((item) => item.asignaturaId == asignatura.id)
            .toList();
        final objetivo =
            datos.objetivos[asignatura.id]?.notaObjetivo ??
            datos.configuracion.notaAprobacion;
        final entradas = evaluacionesAsignatura.map((evaluacion) {
          return EntradaCalculoNota(
            id: evaluacion.id,
            nombre: evaluacion.titulo,
            ponderacion: evaluacion.ponderacion,
            notaReal: datos.calificaciones[evaluacion.id]?.nota,
            notaHipotetica: resolucion.notasHipoteticas[evaluacion.id],
          );
        }).toList();
        final resultado = _calculoNotasService.calcular(
          evaluaciones: entradas,
          configuracion: datos.configuracion,
          objetivo: objetivo,
          configuracionAsignatura:
              datos.configuracionesCalculo[asignatura.id] ??
              ConfiguracionCalculoAsignatura.directa(asignatura.id),
          notaPresentacionHipotetica: _doubleArgument(
            argumentos['notaPresentacionHipotetica'],
          ),
          notaExamenHipotetica: _doubleArgument(
            argumentos['notaExamenHipotetica'],
          ),
          objetivoPresentacion: _doubleArgument(
            argumentos['objetivoPresentacion'],
          ),
        );

        return <String, Object?>{
          'asignatura': asignatura.nombre,
          'objetivo': objetivo,
          'nivelEducativo': datos.nivelEducativo.valorFirestore,
          'escala': {
            'minima': datos.configuracion.notaMinima,
            'maxima': datos.configuracion.notaMaxima,
            'aprobacion': datos.configuracion.notaAprobacion,
          },
          ...resultado.toStructuredMap(),
          'evaluaciones': evaluacionesAsignatura.map((evaluacion) {
            final nota = datos.calificaciones[evaluacion.id]?.nota;
            final hipotetica = resolucion.notasHipoteticas[evaluacion.id];
            final ponderacion = evaluacion.ponderacion;
            return <String, Object?>{
              'nombre': evaluacion.titulo,
              'fecha': _fecha(evaluacion.fecha),
              'notaReal': nota,
              'notaHipotetica': hipotetica,
              'pendiente': nota == null,
              'ponderacion': ponderacion,
              'aporteFinal': (nota ?? hipotetica) != null && ponderacion != null
                  ? (nota ?? hipotetica)! * ponderacion / 100
                  : null,
            };
          }).toList(),
        };
      }).toList();

      _registrarDiagnostico('analizar_notas_completed', {
        'cantidadAsignaturas': analisis.length,
        'cantidadAdvertencias': resolucion.advertencias.length,
        'resultados': analisis
            .map((item) {
              return {
                'resultKeys': item.keys.toList(growable: false),
                'estadoAcademico': item['estadoAcademico'],
                'evaluado': item['evaluado'],
                'tieneResultadoFinal': item['resultadoFinalProyectado'] != null,
                'tienePromedioNecesario':
                    item['promedioNecesarioRestante'] != null,
                'tieneNotaNecesariaExamen': item['notaNecesariaExamen'] != null,
              };
            })
            .toList(growable: false),
      });

      return {
        'exito': true,
        'fechaActual': _fechaActual(),
        'escenarioPersistido': false,
        'advertencias': resolucion.advertencias,
        'reglaInterpretacion': 'Si hay varias evaluaciones pendientes, promedioNecesarioRestante corresponde al promedio de todo el peso restante; no es una nota exacta para la próxima evaluación. notaNecesariaSiQuedaUna solo aparece cuando queda exactamente una evaluación ponderada.',
        'asignaturas': analisis,
      };
    } catch (error, stackTrace) {
      _registrarDiagnostico('analizar_notas_failed', {
        'errorType': error.runtimeType.toString(),
      });
      debugPrintStack(
        label: 'EducFlow AI analizarNotas stack trace',
        stackTrace: stackTrace,
      );
      return {
        'exito': false,
        'fechaActual': _fechaActual(),
        'error': 'No fue posible cargar el módulo de notas. No estimes ni inventes cálculos; informa al usuario que debe revisar la configuración o la conexión.',
      };
    }
  }

  void _registrarDiagnostico(String evento, Map<String, Object?> detalles) {
    assert(() {
      debugPrint('[EducFlow AI][$evento] $detalles');
      return true;
    }());
  }

  User _usuarioActual() {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('No existe un usuario autenticado.');
    }

    return user;
  }

  double? _doubleArgument(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
  }

  String _fechaActual() {
    final DateTime now = DateTime.now();

    return '${_fecha(now)}T'
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }

  String _fecha(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String? _fechaNullable(DateTime? date) => date == null ? null : _fecha(date);

  String? _nullable(String? value) {
    final String clean = value?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }
}
