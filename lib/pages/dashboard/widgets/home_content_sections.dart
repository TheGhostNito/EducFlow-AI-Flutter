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
    final List<Widget> visible = [
      if (preferences.summaryVisible && summary != null) summary!,
      if (preferences.smartSummaryVisible && smartSummary != null)
        smartSummary!,
      if (preferences.nextTaskVisible && nextTask != null) nextTask!,
      if (preferences.nextEvaluationVisible && nextEvaluation != null)
        nextEvaluation!,
      if (preferences.studyRemindersVisible && studyReminder != null)
        studyReminder!,
      if (preferences.todayClassesVisible && todayClasses != null)
        todayClasses!,
      if (preferences.subjectsVisible && subjects != null) subjects!,
    ];

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
