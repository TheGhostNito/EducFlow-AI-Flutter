import 'package:eduflow_ai/widgets/form_sticky_action_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget buildApp({
    required Widget body,
    bool saving = false,
    VoidCallback? onCancel,
    VoidCallback? onSave,
  }) {
    return MaterialApp(
      home: Scaffold(
        extendBody: true,
        body: body,
        bottomNavigationBar: FormStickyActionBar(
          cancelLabel: 'Cancelar',
          saveLabel: 'Guardar cambios',
          saving: saving,
          onCancel: onCancel ?? () {},
          onSave: onSave ?? () {},
        ),
      ),
    );
  }

  testWidgets('las acciones siguen visibles al recorrer contenido largo', (
    tester,
  ) async {
    final controller = ScrollController();

    await tester.pumpWidget(
      buildApp(
        body: ListView(
          controller: controller,
          padding: EdgeInsets.only(
            bottom: FormStickyActionBar.contentClearance(400),
          ),
          children: const [
            SizedBox(height: 900, child: Text('Inicio del formulario')),
            SizedBox(
              key: Key('last-content'),
              height: 80,
              child: Text('Último contenido'),
            ),
          ],
        ),
      ),
    );

    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const Key('last-content')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);
    expect(find.byKey(const Key('last-content')), findsOneWidget);

    final double lastContentBottom = tester
        .getBottomLeft(find.byKey(const Key('last-content')))
        .dy;
    final double actionBarTop = tester
        .getTopLeft(find.byType(FormStickyActionBar))
        .dy;

    expect(lastContentBottom, lessThanOrEqualTo(actionBarTop));
  });

  testWidgets(
    'guardar conserva loading y ambas acciones quedan deshabilitadas',
    (tester) async {
      await tester.pumpWidget(
        buildApp(body: const SizedBox.expand(), saving: true),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Guardar cambios'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets('cancelar y guardar conservan sus callbacks', (tester) async {
    int cancellations = 0;
    int saves = 0;

    await tester.pumpWidget(
      buildApp(
        body: const SizedBox.expand(),
        onCancel: () => cancellations++,
        onSave: () => saves++,
      ),
    );

    await tester.tap(find.text('Cancelar'));
    await tester.tap(find.text('Guardar cambios'));

    expect(cancellations, 1);
    expect(saves, 1);
  });

  testWidgets('en ancho pequeño apila las acciones sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(300, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildApp(body: const SizedBox.expand()));

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('Guardar cambios')).dy,
      lessThan(tester.getTopLeft(find.text('Cancelar')).dy),
    );
  });

  test(
    'el controlador invoca el guardado registrado por el formulario',
    () async {
      final controller = FormSubmitController();
      int submissions = 0;

      Future<void> submit() async {
        submissions++;
      }

      controller.attach(submit);
      await controller.submit();
      controller.detach(submit);
      await controller.submit();

      expect(submissions, 1);
    },
  );
}
