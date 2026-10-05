import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/nota.dart';
import '../models/perfil_usuario.dart';
import '../models/ai_conversation.dart';
import '../models/tarea.dart';
import 'asignaturas_service.dart';
import 'ai_function_calling_flow.dart';
import 'analisis_notas_ia_service.dart';
import 'calculo_notas_service.dart';
import 'evaluaciones_service.dart';
import 'notas_service.dart';
import 'perfil_service.dart';
import 'tareas_service.dart';

abstract interface class AiAssistantClient {
  void iniciarNuevoChat();

  void iniciarConversacion({
    required String conversationId,
    List<AiChatMessage> history = const [],
  });

  Future<String> enviarMensaje(String mensaje);
}

class AiService implements AiAssistantClient {
  AiService._();

  static final AiService instance = AiService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PerfilService _perfilService = PerfilService();
  final AsignaturasService _asignaturasService = AsignaturasService.instance;
  final TareasService _tareasService = TareasService.instance;
  final EvaluacionesService _evaluacionesService = EvaluacionesService.instance;
  final NotasService _notasService = NotasService.instance;
  final CalculoNotasService _calculoNotasService = const CalculoNotasService();
  final AnalisisNotasIaService _analisisNotasIaService =
      const AnalisisNotasIaService();
  late final AiFunctionCallingFlow _functionCallingFlow = AiFunctionCallingFlow(
    logger: _registrarDiagnostico,
  );

  ChatSession? _chat;
  String? _chatUid;

  late final GenerativeModel _model = FirebaseAI.googleAI().generativeModel(
    model: 'gemini-3.5-flash',
    generationConfig: GenerationConfig(
      temperature: 0.35,
      maxOutputTokens: 1800,
    ),
    systemInstruction: Content.system('''
Eres EducFlow AI, el asistente académico inteligente de la aplicación EducFlow AI.

Tu objetivo es ayudar al usuario a entender y organizar su información académica de forma clara, natural y útil.

REGLAS IMPORTANTES:
- Responde en el mismo idioma en que te escriba el usuario, salvo que te pida otro.
- No inventes información académica.
- Cuando una pregunta dependa de datos reales de EducFlow, usa las herramientas disponibles.
- Los datos devueltos por las herramientas son la fuente de verdad.
- Para notas, promedios, objetivos y proyecciones usa siempre analizarNotas. No recalcules ni inventes resultados: interpreta el resultado determinista que entrega esa herramienta.
- Puedes usar varias herramientas para una misma respuesta.
- Si un dato no está disponible, dilo claramente.
- Para referencias como hoy, mañana, esta semana, pendientes o próximas evaluaciones, usa la fecha actual devuelta por las herramientas.
- Por ahora solo tienes herramientas de lectura. No afirmes que modificaste, creaste, completaste o eliminaste información.
- Si el usuario pide modificar datos, explica brevemente que comprendiste la solicitud pero que la confirmación de cambios se habilitará en la siguiente etapa.
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
    _chat = null;
    _chatUid = null;
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

    _chat = _model.startChat(
      history: _buildModelHistory(history),
      maxTurns: 40,
    );

    _chatUid = user.uid;
  }

  ChatSession _obtenerChat(String uid) {
    if (_chat == null || _chatUid != uid) {
      _chat = _model.startChat(maxTurns: 40);
      _chatUid = uid;
    }

    return _chat!;
  }

  List<Content> _buildModelHistory(List<AiChatMessage> messages) {
    final List<AiChatMessage> valid = messages
        .where((message) => !message.isError && message.text.trim().isNotEmpty)
        .toList();

    if (valid.length > 24) {
      valid.removeRange(0, valid.length - 24);
    }

    while (valid.isNotEmpty && valid.first.role == AiChatRole.assistant) {
      valid.removeAt(0);
    }

    while (valid.isNotEmpty && valid.last.role == AiChatRole.user) {
      valid.removeLast();
    }

    return valid.map((message) {
      if (message.role == AiChatRole.user) {
        return Content.text(message.text);
      }

      return Content.model([TextPart(message.text)]);
    }).toList();
  }

  @override
  Future<String> enviarMensaje(String mensaje) async {
    final String texto = mensaje.trim();

    if (texto.isEmpty) {
      throw ArgumentError('El mensaje no puede estar vacío.');
    }

    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('No existe un usuario autenticado.');
    }

    final ChatSession chat = _obtenerChat(user.uid);
    try {
      return await _functionCallingFlow.run(
        sendInitialMessage: () async {
          final response = await chat.sendMessage(Content.text(texto));
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
    } on AiRequestTimeoutException {
      // El Future remoto puede completar más tarde. Descartamos esta sesión
      // para que un reintento no quede ligado a un turno de resultado incierto.
      _chat = null;
      _chatUid = null;
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
    switch (nombre) {
      case 'obtenerPerfil':
        return _obtenerPerfil();
      case 'obtenerAsignaturas':
        return _obtenerAsignaturas();
      case 'obtenerHorario':
        return _obtenerHorario();
      case 'obtenerTareas':
        return _obtenerTareas();
      case 'obtenerEvaluaciones':
        return _obtenerEvaluaciones();
      case 'analizarNotas':
        return _obtenerAnalisisNotas(argumentos);
      default:
        return {
          'exito': false,
          'error': 'Herramienta no implementada: $nombre',
        };
    }
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
    final List<Asignatura> asignaturas = await _asignaturasService
        .obtenerTodas();
    final List<Map<String, Object?>> clases = [];

    for (final Asignatura asignatura in asignaturas) {
      for (final BloqueHorario bloque in asignatura.horario) {
        final String salaBloque = bloque.sala?.trim() ?? '';
        final String salaAsignatura = asignatura.sala?.trim() ?? '';

        clases.add({
          'asignatura': asignatura.nombre,
          'sigla': _nullable(asignatura.sigla),
          'dia': bloque.dia.valorFirestore,
          'horaInicio': bloque.horaInicio,
          'horaFin': bloque.horaFin,
          'sala': salaBloque.isNotEmpty
              ? salaBloque
              : salaAsignatura.isNotEmpty
              ? salaAsignatura
              : null,
          'profesor': _nullable(asignatura.profesor),
          'seccion': _nullable(asignatura.seccion),
        });
      }
    }

    clases.sort((a, b) {
      final int dayA = _ordenDia(a['dia']?.toString() ?? '');
      final int dayB = _ordenDia(b['dia']?.toString() ?? '');

      if (dayA != dayB) {
        return dayA.compareTo(dayB);
      }

      return (a['horaInicio']?.toString() ?? '').compareTo(
        b['horaInicio']?.toString() ?? '',
      );
    });

    final DateTime now = DateTime.now();

    return {
      'exito': true,
      'fechaActual': _fechaActual(),
      'diaActual': _nombreDia(now.weekday),
      'diaManana': _nombreDia(now.add(const Duration(days: 1)).weekday),
      'cantidadBloques': clases.length,
      'clases': clases,
    };
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

  int _ordenDia(String value) {
    switch (value) {
      case 'lunes':
        return 1;
      case 'martes':
        return 2;
      case 'miercoles':
        return 3;
      case 'jueves':
        return 4;
      case 'viernes':
        return 5;
      case 'sabado':
        return 6;
      default:
        return 7;
    }
  }

  String _nombreDia(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'lunes';
      case DateTime.tuesday:
        return 'martes';
      case DateTime.wednesday:
        return 'miercoles';
      case DateTime.thursday:
        return 'jueves';
      case DateTime.friday:
        return 'viernes';
      case DateTime.saturday:
        return 'sabado';
      case DateTime.sunday:
        return 'domingo';
      default:
        return '';
    }
  }
}
