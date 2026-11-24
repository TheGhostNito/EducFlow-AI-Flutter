import 'dart:async';

import 'package:eduflow_ai/pages/subjects/subjects_page.dart';
import 'package:eduflow_ai/widgets/app_swipe_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget tutorialHost(SwipeTutorialPreferences preferences) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: AppSwipeDelete(
            tutorialKey: 'tutorial-user-a',
            tutorialTitle: 'Tutorial',
            tutorialMessage: 'Desliza para eliminar',
            tutorialButtonLabel: 'Entendido',
            tutorialPreferences: preferences,
            deleteLabel: 'Eliminar',
            onConfirmDelete: () async => false,
            onDelete: () async {},
            child: const SizedBox(height: 140),
          ),
        ),
      ),
    );
  }

  test('la clave del tutorial es distinta para cada UID autenticado', () {
    expect(
      SubjectsPage.swipeTutorialKeyForUid('usuario-a'),
      'educflow-swipe-delete-subjects-v2-usuario-a',
    );
    expect(
      SubjectsPage.swipeTutorialKeyForUid('usuario-b'),
      'educflow-swipe-delete-subjects-v2-usuario-b',
    );
    expect(SubjectsPage.swipeTutorialKeyForUid(null), isNull);
  });

  testWidgets('un usuario que ya vio el tutorial no vuelve a recibirlo', (
    tester,
  ) async {
    final _FakeTutorialPreferences preferences = _FakeTutorialPreferences(
      seen: true,
    );

    await tester.pumpWidget(tutorialHost(preferences));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Tutorial'), findsNothing);
    expect(preferences.readKeys, ['tutorial-user-a']);
    expect(preferences.writeKeys, isEmpty);
  });

  testWidgets('Entendido espera y verifica la escritura antes de cerrar', (
    tester,
  ) async {
    final Completer<bool> writeCompleter = Completer<bool>();
    final _FakeTutorialPreferences preferences = _FakeTutorialPreferences(
      seen: false,
      writeCompleter: writeCompleter,
    );

    await tester.pumpWidget(tutorialHost(preferences));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tutorial'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await tester.pump();
    expect(find.text('Tutorial'), findsOneWidget);
    expect(preferences.writeKeys, ['tutorial-user-a']);

    writeCompleter.complete(true);
    await tester.pump();
    expect(find.text('Tutorial'), findsNothing);
    await _finishTutorialAnimation(tester);
  });

  testWidgets('un fallo de persistencia no rompe ni bloquea la interfaz', (
    tester,
  ) async {
    final _FakeTutorialPreferences preferences = _FakeTutorialPreferences(
      readError: StateError('lectura fallida'),
      writeError: StateError('escritura fallida'),
    );

    await tester.pumpWidget(tutorialHost(preferences));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Tutorial'), findsOneWidget);

    await tester.tap(find.text('Entendido'));
    await tester.pump();

    expect(find.text('Tutorial'), findsNothing);
    expect(tester.takeException(), isNull);
    await _finishTutorialAnimation(tester);
  });
}

Future<void> _finishTutorialAnimation(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 300));
}

class _FakeTutorialPreferences implements SwipeTutorialPreferences {
  _FakeTutorialPreferences({
    this.seen,
    this.readError,
    this.writeError,
    this.writeCompleter,
  });

  bool? seen;
  final Object? readError;
  final Object? writeError;
  final Completer<bool>? writeCompleter;
  final List<String> readKeys = [];
  final List<String> writeKeys = [];

  @override
  Future<bool?> readSeen(String key) async {
    readKeys.add(key);
    if (readError != null) throw readError!;
    return seen;
  }

  @override
  Future<bool> writeSeen(String key) async {
    writeKeys.add(key);
    if (writeError != null) throw writeError!;
    if (writeCompleter != null) return writeCompleter!.future;
    seen = true;
    return true;
  }
}
