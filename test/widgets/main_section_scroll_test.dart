import 'package:eduflow_ai/widgets/main_bottom_nav.dart';
import 'package:eduflow_ai/widgets/main_section_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ionicons/ionicons.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(FirebaseAuthTestHost().initialize);

  Future<ScrollController> showPage(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Stack(
              children: [
                ListView.builder(
                  controller: controller,
                  itemExtent: 80,
                  itemCount: 40,
                  itemBuilder: (_, index) => Text('Elemento $index'),
                ),
                MainBottomNav(
                  currentIndex: 0,
                  onHome: () => scrollMainSectionToTop(context, controller),
                  onSchedule: () {},
                  onAi: () {},
                  onCalendar: () {},
                  onNotifications: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return controller;
  }

  testWidgets('tocar la pestaña seleccionada anima hasta el inicio', (
    tester,
  ) async {
    final controller = await showPage(tester);
    controller.jumpTo(900);
    await tester.pump();

    await tester.tap(find.byIcon(Ionicons.home));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(900));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.offset, 0);

    // Un segundo toque estando arriba no inicia un desplazamiento extraño.
    await tester.tap(find.byIcon(Ionicons.home));
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.offset, 0);
  });

  testWidgets('movimiento reducido vuelve arriba sin animación', (
    tester,
  ) async {
    final controller = await showPage(tester, reduceMotion: true);
    controller.jumpTo(900);
    await tester.pump();

    await tester.tap(find.byIcon(Ionicons.home));
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.offset, 0);
  });
}
