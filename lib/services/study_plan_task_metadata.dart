import '../models/tarea.dart';

abstract final class StudyPlanTaskMetadata {
  static final RegExp _marker = RegExp(
    r'\[EDUFLOW_PLAN_ESTUDIO:([^:\]\r\n]+):([^\]\r\n]+)\]',
  );

  static bool isStudySession(Tarea task) =>
      markers(task.descripcion).isNotEmpty;

  static List<String> markers(String? description) => _marker
      .allMatches(description ?? '')
      .map((match) => match.group(0)!)
      .toList(growable: false);

  static String visibleDescription(String? description) =>
      (description ?? '').replaceAll(_marker, '').trim();

  static String? preserveMarkers({
    required String? originalDescription,
    required String? editedVisibleDescription,
  }) {
    final visible = visibleDescription(editedVisibleDescription);
    final protectedMarkers = markers(originalDescription);
    if (protectedMarkers.isEmpty) return visible.isEmpty ? null : visible;
    final suffix = protectedMarkers.join('\n');
    return visible.isEmpty ? suffix : '$visible\n$suffix';
  }
}
