import '../models/evaluacion.dart';
import '../models/tarea.dart';

enum AcademicInsightKind {
  overdueOrTodayTask,
  imminentEvaluation,
  tomorrowTask,
  upcomingEvaluation,
  upcomingTask,
  busyAcademicDay,
}

class AcademicInsight {
  const AcademicInsight({
    required this.id,
    required this.primary,
    this.secondary,
  });

  final String id;
  final AcademicInsightItem primary;
  final AcademicInsightItem? secondary;

  AcademicInsightKind get kind => primary.kind;
  int get daysUntil => primary.daysUntil;
  Tarea? get task => primary.task;
  Evaluacion? get evaluation => primary.evaluation;
  int get todayClassCount => primary.todayClassCount;
  Tarea? get secondaryTask => secondary?.task;
  Evaluacion? get secondaryEvaluation => secondary?.evaluation;
}

class AcademicInsightItem {
  const AcademicInsightItem({
    required this.id,
    required this.kind,
    required this.daysUntil,
    required this.rank,
    this.task,
    this.evaluation,
    this.todayClassCount = 0,
  });

  final String id;
  final AcademicInsightKind kind;
  final int daysUntil;
  final int rank;
  final Tarea? task;
  final Evaluacion? evaluation;
  final int todayClassCount;
}

class AcademicHomePriorityService {
  const AcademicHomePriorityService();

  Tarea? selectNextTask(List<Tarea> tasks, {required DateTime now}) {
    final List<Tarea> candidates = tasks
        .where((task) => task.pendiente && task.fechaEntrega != null)
        .toList();

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final DateTime aDeadline = taskDeadline(a)!;
      final DateTime bDeadline = taskDeadline(b)!;
      final bool aOverdue = aDeadline.isBefore(now);
      final bool bOverdue = bDeadline.isBefore(now);

      if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
      return aOverdue
          ? bDeadline.compareTo(aDeadline)
          : aDeadline.compareTo(bDeadline);
    });

    return candidates.first;
  }

  Evaluacion? selectNextEvaluation(
    List<Evaluacion> evaluations, {
    required DateTime now,
  }) {
    final DateTime today = _dateOnly(now);
    final List<Evaluacion> candidates = evaluations.where((evaluation) {
      final DateTime day = _dateOnly(evaluation.fecha);
      if (day.isBefore(today)) return false;

      final DateTime? exactMoment = evaluationMoment(evaluation);
      return exactMoment == null || !exactMoment.isBefore(now);
    }).toList();

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final DateTime aMoment = evaluationMoment(a) ?? _endOfDay(a.fecha);
      final DateTime bMoment = evaluationMoment(b) ?? _endOfDay(b.fecha);
      return aMoment.compareTo(bMoment);
    });
    return candidates.first;
  }

  AcademicInsight? selectPriority({
    required List<Tarea> tasks,
    required List<Evaluacion> evaluations,
    required int todayClassCount,
    required DateTime now,
    bool nextTaskVisible = true,
    bool nextEvaluationVisible = true,
  }) {
    final Tarea? task = selectNextTask(tasks, now: now);
    final Evaluacion? evaluation = selectNextEvaluation(evaluations, now: now);
    final int? taskDays = task == null
        ? null
        : calendarDaysUntil(task.fechaEntrega!, now);
    final int? evaluationDays = evaluation == null
        ? null
        : calendarDaysUntil(evaluation.fecha, now);

    final List<AcademicInsightItem> relevant = [];
    if (task != null && taskDays! <= 7) {
      final AcademicInsightKind kind = taskDays <= 0
          ? AcademicInsightKind.overdueOrTodayTask
          : taskDays == 1
          ? AcademicInsightKind.tomorrowTask
          : AcademicInsightKind.upcomingTask;
      final int rank = taskDays <= 0
          ? 1
          : taskDays == 1
          ? 3
          : 5;
      relevant.add(_taskInsight(task, kind, taskDays, rank));
    }
    if (evaluation != null && evaluationDays! <= 7) {
      final AcademicInsightKind kind = evaluationDays <= 1
          ? AcademicInsightKind.imminentEvaluation
          : AcademicInsightKind.upcomingEvaluation;
      relevant.add(
        _evaluationInsight(
          evaluation,
          kind,
          evaluationDays,
          evaluationDays <= 1 ? 2 : 4,
        ),
      );
    }
    if (todayClassCount >= 3) {
      final String day = _dateKey(now);
      relevant.add(
        AcademicInsightItem(
          id: 'busy-day:$day',
          kind: AcademicInsightKind.busyAcademicDay,
          daysUntil: 0,
          rank: 7,
          todayClassCount: todayClassCount,
        ),
      );
    }
    if (relevant.isEmpty) return null;
    relevant.sort((a, b) => a.rank.compareTo(b.rank));
    final AcademicInsightItem primary = relevant[0];

    if (relevant.length == 1) {
      final bool duplicatedByNormalCard = primary.task != null
          ? nextTaskVisible
          : primary.evaluation != null
          ? nextEvaluationVisible
          : true;
      if (duplicatedByNormalCard) return null;
      return AcademicInsight(id: primary.id, primary: primary);
    }

    final AcademicInsightItem secondary = relevant[1];
    return AcademicInsight(
      id: '${primary.id}|${secondary.id}',
      primary: primary,
      secondary: secondary,
    );
  }

  DateTime? taskDeadline(Tarea task) {
    final DateTime? date = task.fechaEntrega;
    if (date == null) return null;
    final ({int hour, int minute})? time = _parseTime(task.horaEntrega);
    if (time == null) return _endOfDay(date);
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime? evaluationMoment(Evaluacion evaluation) {
    final ({int hour, int minute})? time = _parseTime(evaluation.hora);
    if (time == null) return null;
    final DateTime date = evaluation.fecha;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  int calendarDaysUntil(DateTime date, DateTime now) {
    return _dateOnly(date).difference(_dateOnly(now)).inDays;
  }

  AcademicInsightItem _taskInsight(
    Tarea task,
    AcademicInsightKind kind,
    int days,
    int rank,
  ) {
    return AcademicInsightItem(
      id: 'task:${task.id}:${_dateKey(task.fechaEntrega!)}',
      kind: kind,
      daysUntil: days,
      rank: rank,
      task: task,
    );
  }

  AcademicInsightItem _evaluationInsight(
    Evaluacion evaluation,
    AcademicInsightKind kind,
    int days,
    int rank,
  ) {
    return AcademicInsightItem(
      id: 'evaluation:${evaluation.id}:${_dateKey(evaluation.fecha)}',
      kind: kind,
      daysUntil: days,
      rank: rank,
      evaluation: evaluation,
    );
  }

  ({int hour, int minute})? _parseTime(String? value) {
    final List<String> parts = value?.trim().split(':') ?? const [];
    if (parts.length != 2) return null;
    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return (hour: hour, minute: minute);
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _endOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  }

  String _dateKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}
