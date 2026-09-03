import 'dart:io';

import 'package:eduflow_ai/pages/dashboard/dashboard_page.dart';
import 'package:eduflow_ai/services/translation_service.dart';
import 'package:eduflow_ai/widgets/app_scroll_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const uid = 'dashboard-menu-test';
  late TranslationService language;

  setUpAll(() async {
    await FirebaseAuthTestHost().initialize(initialUid: uid);
    language = TranslationService.instance;
    SharedPreferences.setMockInitialValues({
      'educflow-user-$uid-beta-0.1-welcome-seen': true,
    });

    // Ahem (fuente por defecto de flutter_test) no reproduce las medidas del
    // texto de la aplicación. Usamos las fuentes que incluye el mismo SDK.
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final loader = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      loader.addFont(
        File(
          '$flutterRoot/bin/cache/artifacts/material_fonts/roboto-$weight.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  });

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const prefix =
        'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
    const codec = StandardMessageCodec();
    // El menú no depende de las consultas académicas. Simulamos un estado
    // sin conexión y aceptamos la persistencia del idioma solo en memoria.
    for (final method in ['documentReferenceGet', 'queryGet']) {
      messenger.setMockMessageHandler(
        '$prefix.$method',
        (_) async => codec.encodeMessage([
          'unavailable',
          'Prueba local sin conexión',
          null,
        ]),
      );
    }
    messenger.setMockMessageHandler(
      '$prefix.documentReferenceSet',
      (_) async => codec.encodeMessage([null]),
    );
    var subscription = 0;
    messenger.setMockMessageHandler('$prefix.querySnapshot', (_) async {
      final id = 'dashboard-menu-${subscription++}';
      messenger.setMockMethodCallHandler(
        MethodChannel('plugins.flutter.io/firebase_firestore/query/$id'),
        (_) async => null,
      );
      return codec.encodeMessage([id]);
    });
  });

  for (final width in [320.0, 390.0, 430.0]) {
    for (final dark in [false, true]) {
      for (final compact in [false, true]) {
        testWidgets(
          'Dashboard: menú exterior ES/EN a $width px, oscuro=$dark, compacto=$compact',
          (tester) async {
            // La altura corta permite alcanzar el encabezado compacto aun
            // cuando el Dashboard no recibe datos académicos del host simulado.
            tester.view.physicalSize = Size(width, compact ? 400 : 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);

            Rect? spanishBounds;
            double? spanishAnchor;
            for (final locale in [AppLanguage.es, AppLanguage.en]) {
              // La persistencia remota está aislada por el host de pruebas.
              await tester.runAsync(() => language.changeLanguage(locale));
              await tester.pumpWidget(
                MaterialApp(
                  theme: ThemeData(
                    useMaterial3: true,
                    platform: TargetPlatform.iOS,
                    brightness: dark ? Brightness.dark : Brightness.light,
                    fontFamily: 'Roboto',
                  ),
                  home: const DashboardPage(),
                ),
              );
              // MainBottomNav contiene una animación continua.
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));

              if (compact) {
                await tester.drag(
                  find.byType(ListView).first,
                  const Offset(0, -220),
                );
                await tester.pump(const Duration(seconds: 1));
              }
              final buttons = find.byWidgetPredicate(
                (widget) => widget is PopupMenuButton,
              );
              final compactButton = find.descendant(
                of: find.byType(AppScrollHeader),
                matching: buttons,
              );
              final button = compact ? compactButton : buttons.first;
              expect(button.hitTestable(), findsOneWidget);
              final anchor = tester.getRect(button).right;
              await tester.tap(button);
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));

              // Medimos el Material que pinta el fondo y borde del popup,
              // no el botón, un texto ni un ConstrainedBox interno.
              final menu = find.byWidgetPredicate(
                (widget) =>
                    widget is Material &&
                    widget.type == MaterialType.card &&
                    widget.shape is RoundedRectangleBorder &&
                    (widget.shape as RoundedRectangleBorder).borderRadius ==
                        BorderRadius.circular(17),
              );
              expect(menu, findsOneWidget);
              final bounds = tester.getRect(menu);
              expect(bounds.width, 200);
              expect(bounds.right, closeTo(anchor.clamp(8, width - 8), 0.01));
              expect(bounds.left, greaterThanOrEqualTo(8));
              if (spanishBounds != null) {
                expect(bounds.left, spanishBounds.left);
                expect(bounds.right, spanishBounds.right);
                expect(bounds.height, spanishBounds.height);
                expect(anchor, spanishAnchor);
              } else {
                spanishBounds = bounds;
                spanishAnchor = anchor;
              }
              final labels = locale == AppLanguage.es
                  ? [
                      'Perfil',
                      'Asignaturas',
                      'Tareas',
                      'Ajustes',
                      'Cerrar sesión',
                    ]
                  : ['Profile', 'Subjects', 'Tasks', 'Settings', 'Sign out'];
              for (final label in labels) {
                final text = find.text(label);
                expect(text, findsOneWidget);
                final textBounds = tester.getRect(text);
                expect(bounds.contains(textBounds.topLeft), isTrue);
                expect(bounds.contains(textBounds.bottomRight), isTrue);
              }
              expect(tester.takeException(), isNull);
              Navigator.of(tester.element(menu)).pop();
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 500));
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          },
        );
      }
    }
  }
}
