import 'package:flutter/widgets.dart';

import '../../../services/home_preferences_service.dart';

class HomeContentSections extends StatelessWidget {
  const HomeContentSections({
    required this.preferences,
    this.summary,
    this.todayClasses,
    this.subjects,
    this.nextTask,
    this.nextEvaluation,
    this.studyReminder,
    this.smartSummary,
    this.emptyState,
    super.key,
  });

  final HomePreferences preferences;
  final Widget? summary;
  final Widget? todayClasses;
  final Widget? subjects;
  final Widget? nextTask;
  final Widget? nextEvaluation;
  final Widget? studyReminder;
  final Widget? smartSummary;
  final Widget? emptyState;

  @override
  Widget build(BuildContext context) {
    final byModule = <HomeModule, Widget?>{
      HomeModule.summary: preferences.summaryVisible ? summary : null,
      HomeModule.nextTask: preferences.nextTaskVisible ? nextTask : null,
      HomeModule.nextEvaluation: preferences.nextEvaluationVisible
          ? nextEvaluation
          : null,
      HomeModule.studyReminders: preferences.studyRemindersVisible
          ? studyReminder
          : null,
      HomeModule.todayClasses: preferences.todayClassesVisible
          ? todayClasses
          : null,
      HomeModule.subjects: preferences.subjectsVisible ? subjects : null,
    };
    final List<Widget> visible = [];
    for (final module in preferences.moduleOrder) {
      final widget = byModule[module];
      if (widget != null) visible.add(widget);
    }
    if (preferences.smartSummaryVisible && smartSummary != null) {
      // Resumen inteligente conserva una posición fija y no participa del
      // orden académico configurable por ahora.
      visible.insert(visible.isEmpty ? 0 : 1, smartSummary!);
    }

    if (visible.isEmpty) return emptyState ?? const SizedBox.shrink();

    return Column(
      children: [
        for (int index = 0; index < visible.length; index++) ...[
          if (index > 0) const SizedBox(height: 18),
          visible[index],
        ],
      ],
    );
  }
}
