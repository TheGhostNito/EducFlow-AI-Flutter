import 'dart:async';

import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/tarea.dart';
import 'ai_academic_query_scope.dart';
import 'ai_function_calling_flow.dart';

enum AiDeterministicQueryKind {
  greeting,
  upcomingEvaluations,
  pendingTasks,
  tasksAndEvaluations,
  subjects,
  schedule,
  teachers,
  rooms,
  gemini,
}

typedef _SubjectSelection = ({
  List<Asignatura> subjects,
  bool filtered,
  String? error,
});

class AiLocalQueryException implements Exception {
  const AiLocalQueryException(this.cause);

  final Object cause;
}

class AiDeterministicQueryService {
  AiDeterministicQueryService({
    required this.loadSubjects,
    required this.loadEvaluations,
    required this.loadTasks,
    DateTime Function()? now,
    this.logger,
    this.maxItems = 8,
    this.dataTimeout = const Duration(seconds: 12),
  }) : _now = now ?? DateTime.now;

  final Future<List<Asignatura>> Function() loadSubjects;
  final Future<List<Evaluacion>> Function() loadEvaluations;
  final Future<List<Tarea>> Function() loadTasks;
  final DateTime Function() _now;
  final AiDiagnosticLogger? logger;
  final int maxItems;
  final Duration dataTimeout;

  AiDeterministicQueryKind classify(String message) {
    final String text = _normalize(message);
    if (text.isEmpty) return AiDeterministicQueryKind.gemini;
    if (_isEnglish(message) &&
        RegExp(r'\b\d{1,2}[/-]\d{1,2}[/-]\d{4}\b').hasMatch(message)) {
      // En inglés el orden día/mes frente a mes/día no es inequívoco.
      return AiDeterministicQueryKind.gemini;
    }

    // Las solicitudes creativas o de recomendación conservan el contexto y el
    // razonamiento de Gemini, aunque mencionen datos académicos.
    const complexMarkers = <String>{
      'aconseja',
      'analiza',
      'compara',
      'explica',
      'genera',
      'planifica',
      'prepara',
      'recomienda',
      'redacta',
      'resume',
      'estrategia',
      'estudiar',
      'mejorar',
    };
    if (_containsAnyWord(text, complexMarkers) ||
        _containsAnyWordStartingWith(text, complexMarkers)) {
      return AiDeterministicQueryKind.gemini;
    }

    final scope = AiDateScope.parse(message, _now());
    if (scope.kind == AiDateScopeKind.unsupported) {
      return AiDeterministicQueryKind.gemini;
    }

    final asksEvaluations = _containsAny(text, const [
      'evaluacion',
      'evaluaciones',
      'examen',
      'examenes',
      'prueba',
      'pruebas',
      'control',
      'controles',
      'certamen',
      'certamenes',
      'assessment',
      'assessments',
      'evaluation',
      'evaluations',
      'exam',
      'exams',
      'test',
      'tests',
    ]);
    final asksTasks =
        _containsAny(text, const [
          'tarea',
          'tareas',
          'entrega',
          'entregas',
          'trabajo pendiente',
          'trabajos pendientes',
          'task',
          'tasks',
          'assignment',
          'assignments',
        ]) ||
        _containsAnyWord(text, const ['tares']);
    if (asksEvaluations && asksTasks && _looksLikeLookup(text)) {
      return scope.kind == AiDateScopeKind.weekday
          ? AiDeterministicQueryKind.gemini
          : AiDeterministicQueryKind.tasksAndEvaluations;
    }

    if (asksEvaluations && _looksLikeLookup(text)) {
      if (scope.kind == AiDateScopeKind.weekday) {
        return AiDeterministicQueryKind.gemini;
      }
      return AiDeterministicQueryKind.upcomingEvaluations;
    }

    if (asksTasks && _looksLikeLookup(text)) {
      if (scope.kind == AiDateScopeKind.weekday) {
        return AiDeterministicQueryKind.gemini;
      }
      return AiDeterministicQueryKind.pendingTasks;
    }

    // "Próximo profesor/sala/ramo" no identifica por sí solo un bloque.
    if (scope.kind == AiDateScopeKind.upcoming) {
      return AiDeterministicQueryKind.gemini;
    }

    if (_containsAny(text, const [
          'profesor',
          'profesora',
          'docente',
          'teacher',
          'teachers',
          'instructor',
          'instructors',
          'teaches',
        ]) &&
        _looksLikeLookup(text)) {
      return AiDeterministicQueryKind.teachers;
    }

    if (_containsAny(text, const [
          'sala',
          'salas',
          'aula',
          'aulas',
          'room',
          'rooms',
          'classroom',
        ]) &&
        _looksLikeLookup(text)) {
      return AiDeterministicQueryKind.rooms;
    }

    if (_containsAny(text, const [
          'horario',
          'clase',
          'clases',
          'schedule',
          'class',
          'classes',
        ]) &&
        _looksLikeLookup(text)) {
      return AiDeterministicQueryKind.schedule;
    }

    if (_containsAny(text, const [
          'asignatura',
          'asignaturas',
          'ramo',
          'ramos',
          'materia',
          'materias',
          'subject',
          'subjects',
          'course',
          'courses',
        ]) &&
        _looksLikeLookup(text)) {
      return AiDeterministicQueryKind.subjects;
    }

    if (_isGreeting(text)) {
      return AiDeterministicQueryKind.greeting;
    }

    return AiDeterministicQueryKind.gemini;
  }

  Future<String?> tryResolve(String message) async {
    final AiDeterministicQueryKind kind = classify(message);
    if (kind == AiDeterministicQueryKind.gemini) return null;

    final Stopwatch stopwatch = Stopwatch()..start();
    _log('deterministic_route_started', {'route': kind.name});
    try {
      final String answer = await _resolve(kind, message).timeout(
        dataTimeout,
        onTimeout: () => throw AiRequestTimeoutException(
          timeout: dataTimeout,
          stage: 'consulta_local',
        ),
      );
      stopwatch.stop();
      _log('deterministic_route_completed', {
        'route': kind.name,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'responseCharacters': answer.length,
      });
      return answer;
    } catch (error) {
      stopwatch.stop();
      _log('deterministic_route_failed', {
        'route': kind.name,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'errorType': error.runtimeType.toString(),
      });
      if (error is AiRequestTimeoutException) rethrow;
      throw AiLocalQueryException(error);
    }
  }

  Future<String> _resolve(AiDeterministicQueryKind kind, String message) async {
    final english = _isEnglish(message);
    return switch (kind) {
      AiDeterministicQueryKind.greeting =>
        english
            ? 'Hello! I am EducFlow AI. I can help with your assessments, tasks, subjects, schedule, teachers, rooms, and academic questions.'
            : '¡Hola! Soy EducFlow AI. Puedo ayudarte con tus evaluaciones, tareas, asignaturas, horarios, profesores, salas y preguntas académicas.',
      AiDeterministicQueryKind.upcomingEvaluations => await _resolveEvaluations(
        message,
      ),
      AiDeterministicQueryKind.pendingTasks => await _resolveTasks(message),
      AiDeterministicQueryKind.tasksAndEvaluations => await _resolveCombined(
        message,
      ),
      AiDeterministicQueryKind.subjects => await _resolveSubjects(message),
      AiDeterministicQueryKind.schedule => await _resolveSchedule(message),
      AiDeterministicQueryKind.teachers => await _resolveTeachers(message),
      AiDeterministicQueryKind.rooms => await _resolveRooms(message),
      AiDeterministicQueryKind.gemini => throw StateError(
        'Una ruta Gemini no debe resolverse localmente.',
      ),
    };
  }

  Future<String> _resolveEvaluations(String message) async {
    final List<dynamic> data = await Future.wait<dynamic>([
      loadEvaluations(),
      loadSubjects(),
    ]);
    final List<Evaluacion> evaluations = data[0] as List<Evaluacion>;
    final List<Asignatura> subjects = data[1] as List<Asignatura>;
    return _formatEvaluations(message, evaluations, subjects);
  }

  Future<String> _resolveCombined(String message) async {
    final List<dynamic> data = await Future.wait<dynamic>([
      loadTasks(),
      loadEvaluations(),
      loadSubjects(),
    ]);
    final selection = _selectSubjects(message, data[2] as List<Asignatura>);
    if (selection.error != null) return selection.error!;
    return '${_formatTasks(message, data[0] as List<Tarea>, data[2] as List<Asignatura>)}\n\n'
        '${_formatEvaluations(message, data[1] as List<Evaluacion>, data[2] as List<Asignatura>)}';
  }

  String _formatEvaluations(
    String message,
    List<Evaluacion> evaluations,
    List<Asignatura> subjects,
  ) {
    final english = _isEnglish(message);
    final selection = _selectSubjects(message, subjects);
    if (selection.error != null) return selection.error!;
    final Map<String, String> subjectNames = {
      for (final Asignatura subject in subjects) subject.id: subject.nombre,
    };
    final scope = AiDateScope.parse(message, _now());
    final selectedIds = selection.subjects.map((item) => item.id).toSet();
    final List<Evaluacion> upcoming =
        evaluations
            .where(
              (item) =>
                  (!selection.filtered ||
                      selectedIds.contains(item.asignaturaId)) &&
                  scope.matches(item.fecha, item.hora, defaultUpcoming: true),
            )
            .toList()
          ..sort(_compareEvaluations);

    if (upcoming.isEmpty) {
      if (evaluations.isEmpty) {
        return english
            ? 'You do not have any registered assessments yet.'
            : 'Todavía no tienes evaluaciones registradas.';
      }
      return scope.kind == AiDateScopeKind.none ||
              scope.kind == AiDateScopeKind.upcoming
          ? _tr(
              english,
              'No tienes próximas evaluaciones registradas.',
              'You have no upcoming assessments registered.',
            )
          : _tr(
              english,
              'No tienes evaluaciones registradas para el período solicitado.',
              'You have no assessments registered for the requested period.',
            );
    }

    final List<String> lines = upcoming.take(maxItems).map((item) {
      final String subject = subjectNames[item.asignaturaId]?.trim() ?? '';
      final String time = _clean(item.hora);
      return '- ${item.titulo}${subject.isEmpty ? '' : ' · $subject'} — '
          '${_formatDate(item.fecha, english: english)}${time.isEmpty
              ? ''
              : english
              ? ' at $time'
              : ' a las $time'}';
    }).toList();
    return _withRemaining(
      scope.kind == AiDateScopeKind.none ||
              scope.kind == AiDateScopeKind.upcoming
          ? _tr(
              english,
              'Tus próximas evaluaciones son:',
              'Your upcoming assessments are:',
            )
          : _tr(
              english,
              'Tus evaluaciones para el período solicitado son:',
              'Your assessments for the requested period are:',
            ),
      lines,
      upcoming.length,
      english: english,
    );
  }

  Future<String> _resolveTasks(String message) async {
    final List<dynamic> data = await Future.wait<dynamic>([
      loadTasks(),
      loadSubjects(),
    ]);
    final List<Tarea> tasks = data[0] as List<Tarea>;
    final List<Asignatura> subjects = data[1] as List<Asignatura>;
    return _formatTasks(message, tasks, subjects);
  }

  String _formatTasks(
    String message,
    List<Tarea> tasks,
    List<Asignatura> subjects,
  ) {
    final english = _isEnglish(message);
    final selection = _selectSubjects(message, subjects);
    if (selection.error != null) return selection.error!;
    final Map<String, String> subjectNames = {
      for (final Asignatura subject in subjects) subject.id: subject.nombre,
    };
    final scope = AiDateScope.parse(message, _now());
    final selectedIds = selection.subjects.map((item) => item.id).toSet();
    final List<Tarea> pending = tasks.where((item) {
      if (!item.pendiente) return false;
      if (selection.filtered && !selectedIds.contains(item.asignaturaId)) {
        return false;
      }
      if (scope.kind == AiDateScopeKind.none) return true;
      return item.fechaEntrega != null &&
          scope.matches(item.fechaEntrega!, item.horaEntrega);
    }).toList()..sort(_compareTasks);

    if (pending.isEmpty) {
      return tasks.isEmpty
          ? _tr(
              english,
              'Todavía no tienes tareas registradas.',
              'You do not have any registered tasks yet.',
            )
          : _tr(
              english,
              'No tienes tareas pendientes para ese período.',
              'You have no pending tasks for that period.',
            );
    }

    final List<String> lines = pending.take(maxItems).map((item) {
      final String subject = item.asignaturaId == null
          ? ''
          : subjectNames[item.asignaturaId]?.trim() ?? '';
      final String time = _clean(item.horaEntrega);
      final String due = item.fechaEntrega == null
          ? _tr(english, 'sin fecha de entrega', 'no due date')
          : '${_formatDate(item.fechaEntrega!, english: english)}${time.isEmpty
                ? ''
                : english
                ? ' at $time'
                : ' a las $time'}';
      return '- ${item.titulo}${subject.isEmpty ? '' : ' · $subject'} — $due';
    }).toList();
    return _withRemaining(
      _tr(english, 'Tus tareas pendientes son:', 'Your pending tasks are:'),
      lines,
      pending.length,
      english: english,
    );
  }

  Future<String> _resolveSubjects(String message) async {
    final english = _isEnglish(message);
    final List<Asignatura> subjects = await loadSubjects();
    if (subjects.isEmpty) {
      return _tr(
        english,
        'Todavía no tienes asignaturas registradas.',
        'You do not have any registered subjects yet.',
      );
    }
    final selection = _selectSubjects(message, subjects);
    if (selection.error != null) return selection.error!;
    final scope = AiDateScope.parse(message, _now());
    final scheduled = _scheduledSubjects(selection.subjects, scope);
    if (scheduled.isEmpty) {
      return _tr(
        english,
        'No tienes asignaturas con clases para el período solicitado.',
        'You have no subjects with classes in the requested period.',
      );
    }
    final List<Asignatura> ordered = [
      ...scheduled,
    ]..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    final List<String> lines = ordered.take(maxItems).map((item) {
      final String code = _clean(item.sigla);
      final String section = _clean(item.seccion);
      return '- ${item.nombre}${code.isEmpty ? '' : ' ($code)'}'
          '${section.isEmpty
              ? ''
              : english
              ? ' · section $section'
              : ' · sección $section'}';
    }).toList();
    return _withRemaining(
      _tr(
        english,
        'Tus asignaturas registradas son:',
        'Your registered subjects are:',
      ),
      lines,
      ordered.length,
      english: english,
    );
  }

  Future<String> _resolveTeachers(String message) async {
    final english = _isEnglish(message);
    final List<Asignatura> subjects = await loadSubjects();
    if (subjects.isEmpty) {
      return _tr(
        english,
        'Todavía no tienes asignaturas registradas.',
        'You do not have any registered subjects yet.',
      );
    }
    final selection = _selectSubjects(message, subjects);
    if (selection.error != null) return selection.error!;
    final scope = AiDateScope.parse(message, _now());
    final matches = _scheduledSubjects(selection.subjects, scope);
    if (matches.isEmpty) {
      return _tr(
        english,
        'No tienes clases registradas para el período solicitado.',
        'You have no registered classes for the requested period.',
      );
    }
    final List<Asignatura> withTeacher = matches
        .where((item) => _clean(item.profesor).isNotEmpty)
        .toList();
    if (withTeacher.isEmpty) {
      return _tr(
        english,
        'No hay profesores registrados para las asignaturas consultadas.',
        'There are no registered teachers for the requested subjects.',
      );
    }
    return '${_tr(english, 'Profesores registrados:', 'Registered teachers:')}\n${withTeacher.take(maxItems).map((item) => '- ${item.nombre}: ${_clean(item.profesor)}').join('\n')}';
  }

  Future<String> _resolveRooms(String message) async {
    final english = _isEnglish(message);
    final List<Asignatura> subjects = await loadSubjects();
    if (subjects.isEmpty) {
      return _tr(
        english,
        'Todavía no tienes asignaturas registradas.',
        'You do not have any registered subjects yet.',
      );
    }
    final selection = _selectSubjects(message, subjects);
    if (selection.error != null) return selection.error!;
    final scope = AiDateScope.parse(message, _now());
    final matches = _scheduledSubjects(selection.subjects, scope);
    if (matches.isEmpty) {
      return _tr(
        english,
        'No tienes clases registradas para el período solicitado.',
        'You have no registered classes for the requested period.',
      );
    }
    final List<String> lines = [];
    for (final Asignatura subject in matches) {
      final blocks = scope.targetWeekday == null
          ? subject.horario
          : subject.horario
                .where((block) => _weekday(block.dia) == scope.targetWeekday)
                .toList();
      final Set<String> rooms = {
        if (scope.kind == AiDateScopeKind.none &&
            _clean(subject.sala).isNotEmpty)
          _clean(subject.sala),
        for (final BloqueHorario block in blocks)
          if (_clean(block.sala).isNotEmpty)
            _clean(block.sala)
          else if (_clean(subject.sala).isNotEmpty)
            _clean(subject.sala),
      };
      if (rooms.isNotEmpty) {
        lines.add('- ${subject.nombre}: ${rooms.join(', ')}');
      }
    }
    if (lines.isEmpty) {
      return _tr(
        english,
        'No hay salas registradas para las asignaturas consultadas.',
        'There are no registered rooms for the requested subjects.',
      );
    }
    return '${_tr(english, 'Salas registradas:', 'Registered rooms:')}\n${lines.take(maxItems).join('\n')}';
  }

  Future<String> _resolveSchedule(String message) async {
    final english = _isEnglish(message);
    final List<Asignatura> subjects = await loadSubjects();
    if (subjects.isEmpty) {
      return _tr(
        english,
        'Todavía no tienes asignaturas registradas.',
        'You do not have any registered subjects yet.',
      );
    }
    final selection = _selectSubjects(message, subjects);
    if (selection.error != null) return selection.error!;
    final scope = AiDateScope.parse(message, _now());
    final int? targetWeekday = scope.targetWeekday;
    final List<({Asignatura subject, BloqueHorario block})> blocks =
        [
          for (final Asignatura subject in selection.subjects)
            for (final BloqueHorario block in subject.horario)
              if (targetWeekday == null || _weekday(block.dia) == targetWeekday)
                (subject: subject, block: block),
        ]..sort((a, b) {
          final int day = _weekday(a.block.dia)
              .compareTo(_weekday(b.block.dia));
          return day != 0
              ? day
              : a.block.horaInicio.compareTo(b.block.horaInicio);
        });
    if (blocks.isEmpty) {
      return targetWeekday == null
          ? _tr(
              english,
              'Todavía no tienes bloques de horario registrados.',
              'You do not have any registered schedule blocks yet.',
            )
          : _tr(
              english,
              'No tienes clases registradas para ${_weekdayName(targetWeekday)}.',
              'You have no registered classes for ${_weekdayName(targetWeekday, english: true)}.',
            );
    }
    final List<String> lines = blocks.take(maxItems).map((entry) {
      final String room = _clean(entry.block.sala).isNotEmpty
          ? _clean(entry.block.sala)
          : _clean(entry.subject.sala);
      return '- ${_weekdayName(_weekday(entry.block.dia), english: english)}: '
          '${entry.subject.nombre}, ${entry.block.horaInicio}–${entry.block.horaFin}'
          '${room.isEmpty
              ? ''
              : english
              ? ' · room $room'
              : ' · sala $room'}';
    }).toList();
    return _withRemaining(
      scope.kind == AiDateScopeKind.none ||
              scope.kind == AiDateScopeKind.weekday
          ? _tr(
              english,
              'Tu horario recurrente consultado es:',
              'Your recurring schedule is:',
            )
          : _tr(
              english,
              'Tu horario recurrente para el período solicitado es:',
              'Your recurring schedule for the requested period is:',
            ),
      lines,
      blocks.length,
      english: english,
    );
  }

  List<Asignatura> _scheduledSubjects(
    List<Asignatura> subjects,
    AiDateScope scope,
  ) {
    final target = scope.targetWeekday;
    if (target != null) {
      return subjects
          .where(
            (subject) =>
                subject.horario.any((block) => _weekday(block.dia) == target),
          )
          .toList();
    }
    if (scope.kind == AiDateScopeKind.thisWeek ||
        scope.kind == AiDateScopeKind.nextWeek) {
      return subjects.where((subject) => subject.horario.isNotEmpty).toList();
    }
    return subjects;
  }

  _SubjectSelection _selectSubjects(String message, List<Asignatura> subjects) {
    final english = _isEnglish(message);
    final String normalized = _normalize(message);
    final List<Asignatura> named = subjects.where((subject) {
      final String name = _normalize(subject.nombre);
      final String code = _normalize(subject.sigla ?? '');
      return name.isNotEmpty && containsAcademicPhrase(normalized, name) ||
          code.isNotEmpty && containsAcademicPhrase(normalized, code);
    }).toList();
    if (named.isNotEmpty) {
      final codeMatches = named.where((item) {
        final code = _normalize(item.sigla ?? '');
        return code.isNotEmpty && containsAcademicPhrase(normalized, code);
      }).toList();
      if (codeMatches.length == 1) {
        return (subjects: codeMatches, filtered: true, error: null);
      }
      final sectionMatch = RegExp(r'\b(?:seccion|section)\s+([a-z0-9]+)\b')
          .firstMatch(normalized);
      if (sectionMatch != null) {
        final sectionMatches = named
            .where((item) => _normalize(item.seccion ?? '') == sectionMatch[1])
            .toList();
        if (sectionMatches.length == 1) {
          return (subjects: sectionMatches, filtered: true, error: null);
        }
      }
      final candidates = codeMatches.length > 1 ? codeMatches : named;
      final longest = candidates
          .map((item) => item.nombre.length)
          .reduce((a, b) => a > b ? a : b);
      final matches = candidates
          .where((item) => item.nombre.length == longest)
          .toList();
      if (codeMatches.length <= 1 &&
          matches.length == 1 &&
          candidates.every(
            (item) => containsAcademicPhrase(
              _normalize(matches.single.nombre),
              _normalize(item.nombre),
            ),
          )) {
        return (subjects: matches, filtered: true, error: null);
      }
      final labels = candidates
          .map((item) {
            final section = _clean(item.seccion);
            return section.isEmpty
                ? item.nombre
                : '${item.nombre} · ${english ? 'section' : 'sección'} $section';
          })
          .join(', ');
      return (
        subjects: const <Asignatura>[],
        filtered: true,
        error: english
            ? 'I found several possible subjects ($labels). Specify the section or course code.'
            : 'Encontré varias asignaturas posibles ($labels). Indica la sección o sigla para precisar la consulta.',
      );
    }

    final candidate = _requestedSubject(message);
    if (candidate != null) {
      return (
        subjects: const <Asignatura>[],
        filtered: true,
        error: english
            ? 'I could not find the subject "$candidate" among your registered subjects.'
            : 'No encontré la asignatura "$candidate" entre tus asignaturas registradas.',
      );
    }
    return (subjects: subjects, filtered: false, error: null);
  }

  String? _requestedSubject(String message) {
    final text = _normalize(message);
    final match = RegExp(
      r'\b(?:me hace|sala tengo|sala esta|(?:asignatura|ramo|materia)\s+|(?:profesor|profesora|sala|aula|horario|clase|clases|tarea|tareas|evaluacion|evaluaciones)\s+(?:de|del|en|para)\s+|(?:profesor|profesora|sala|aula|horario|clase|clases|tarea|tareas|evaluacion|evaluaciones)\s+tengo\s+(?:de|en|para)\s+|(?:teaches|teacher of|room for|room in|subject|course|class in|classes in|tasks for|assessments for|tasks do i have for|assessments do i have for|classes do i have in)\s+)(.+)$',
    ).firstMatch(text);
    if (match == null) return null;
    var candidate = match[1]!.trim();
    candidate = candidate
        .replaceAll(
          RegExp(
            r'\b(hoy|manana|esta semana|proxima semana|la semana que viene|proximas?|pendientes?|registradas?|tengo|hay|son|es|today|tomorrow|this week|next week|upcoming|pending|registered|have|do)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (AiDateScope.parse(message, _now()).kind == AiDateScopeKind.exactDate) {
      candidate = candidate
          .replaceAll(RegExp(r'\b\d{1,4}\b'), '')
          .replaceAll(
            RegExp(
              r'\b(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre)\b',
            ),
            '',
          )
          .replaceAll(RegExp(r'\b(el|la|de|del|para|en|on|the|for)\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    if (candidate.isEmpty ||
        candidate == 'mis' ||
        candidate == 'mi' ||
        candidate == 'todas' ||
        candidate == 'todos' ||
        candidate == 'la' ||
        candidate == 'el' ||
        candidate == 'my' ||
        candidate == 'the') {
      return null;
    }
    return candidate;
  }

  bool _looksLikeLookup(String text) {
    if (_containsAnyWord(text, const [
      'cual',
      'cuales',
      'cuando',
      'donde',
      'que',
      'quien',
      'what',
      'which',
      'when',
      'where',
      'who',
    ])) {
      return true;
    }

    return _containsAny(text, const [
      'que tengo',
      'lista',
      'muestra',
      'mis ',
      'mi ',
      'pendiente',
      'pendientes',
      'proxima',
      'proximas',
      'hoy',
      'manana',
      'esta semana',
      'proxima semana',
      'horario',
      'my ',
      'show',
      'list',
      'today',
      'tomorrow',
      'this week',
      'next week',
      'schedule',
    ]);
  }

  bool _isGreeting(String text) {
    final remaining = text
        .replaceAll(
          RegExp(
            r'\b(hola|buenos dias|buenas tardes|buenas noches|hey|hello|hi)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return remaining.isEmpty && text.isNotEmpty;
  }

  bool _isEnglish(String message) {
    final text = _normalize(message);
    return _containsAnyWord(text, const ['hello', 'hi', 'hey']) ||
        _containsAnyWord(text, const [
          'what',
          'when',
          'where',
          'which',
          'who',
          'show',
          'list',
          'today',
          'tomorrow',
          'teacher',
          'teachers',
          'subjects',
          'tasks',
          'assessments',
          'schedule',
        ]);
  }

  bool _containsAny(String text, Iterable<String> values) =>
      values.any(text.contains);

  bool _containsAnyWord(String text, Iterable<String> values) =>
      values.any((value) => _containsWord(text, value));

  bool _containsAnyWordStartingWith(String text, Iterable<String> prefixes) {
    final List<String> words = text.split(' ');
    return prefixes.any(
      (prefix) => words.any((word) => word.startsWith(prefix)),
    );
  }

  bool _containsWord(String text, String word) =>
      RegExp('(?:^| )${RegExp.escape(word)}(?: |\u0024)').hasMatch(text);

  String _normalize(String value) => normalizeAcademicQuery(value);

  int _compareEvaluations(Evaluacion a, Evaluacion b) {
    final int date = a.fecha.compareTo(b.fecha);
    if (date != 0) return date;
    return _clean(a.hora).compareTo(_clean(b.hora));
  }

  int _compareTasks(Tarea a, Tarea b) {
    final DateTime? aDate = a.fechaEntrega;
    final DateTime? bDate = b.fechaEntrega;
    if (aDate == null && bDate != null) return 1;
    if (aDate != null && bDate == null) return -1;
    if (aDate != null && bDate != null) {
      final int date = aDate.compareTo(bDate);
      if (date != 0) return date;
    }
    return _clean(a.horaEntrega).compareTo(_clean(b.horaEntrega));
  }

  String _formatDate(DateTime date, {bool english = false}) {
    const months = <String>[
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    if (english) {
      const englishMonths = <String>[
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${date.day} ${englishMonths[date.month - 1]} ${date.year}';
    }
    return '${date.day} de ${months[date.month - 1]} de ${date.year}';
  }

  int _weekday(DiaSemana day) => switch (day) {
    DiaSemana.lunes => DateTime.monday,
    DiaSemana.martes => DateTime.tuesday,
    DiaSemana.miercoles => DateTime.wednesday,
    DiaSemana.jueves => DateTime.thursday,
    DiaSemana.viernes => DateTime.friday,
    DiaSemana.sabado => DateTime.saturday,
  };

  String _weekdayName(int weekday, {bool english = false}) => english
      ? switch (weekday) {
          DateTime.monday => 'Monday',
          DateTime.tuesday => 'Tuesday',
          DateTime.wednesday => 'Wednesday',
          DateTime.thursday => 'Thursday',
          DateTime.friday => 'Friday',
          DateTime.saturday => 'Saturday',
          DateTime.sunday => 'Sunday',
          _ => 'that day',
        }
      : switch (weekday) {
          DateTime.monday => 'lunes',
          DateTime.tuesday => 'martes',
          DateTime.wednesday => 'miércoles',
          DateTime.thursday => 'jueves',
          DateTime.friday => 'viernes',
          DateTime.saturday => 'sábado',
          DateTime.sunday => 'domingo',
          _ => 'ese día',
        };

  String _withRemaining(
    String title,
    List<String> lines,
    int total, {
    bool english = false,
  }) {
    final int remaining = total - lines.length;
    return '$title\n${lines.join('\n')}'
        '${remaining > 0
            ? english
                  ? '\n…and $remaining more.'
                  : '\n…y $remaining más.'
            : ''}';
  }

  String _tr(bool english, String spanish, String translated) =>
      english ? translated : spanish;

  String _clean(String? value) => value?.trim() ?? '';

  void _log(String event, Map<String, Object?> details) {
    logger?.call(event, details);
  }
}
