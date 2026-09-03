import 'dart:async';

import 'package:eduflow_ai/pages/login/login_page.dart';
import 'package:eduflow_ai/pages/register/register_page.dart';
import 'package:eduflow_ai/services/translation_service.dart';
import 'package:eduflow_ai/widgets/app_animated_visibility.dart';
import 'package:eduflow_ai/widgets/auth_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/firebase_auth_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final host = FirebaseAuthTestHost();
  setUpAll(host.initialize);
  setUp(() {
    host.reset();
    TranslationService.instance.resetForSignedOutUser();
  });

  Future<void> mostrar(
    WidgetTester tester,
    Widget page, {
    bool oscuro = false,
    double ancho = 390,
    double escalaTexto = 1,
  }) async {
    tester.view.physicalSize = Size(ancho, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: oscuro ? Brightness.dark : Brightness.light,
          scaffoldBackgroundColor: oscuro
              ? const Color(0xFF0D0D10)
              : const Color(0xFFF6F7FB),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(escalaTexto)),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> escribir(WidgetTester tester, int campo, String texto) async {
    final finder = find.byType(TextField).at(campo);
    await tester.ensureVisible(finder);
    await tester.enterText(finder, texto);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
  }

  Future<void> enviar(WidgetTester tester) async {
    final button = find.byType(ElevatedButton);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  AppAnimatedVisibility aviso(String text, WidgetTester tester) =>
      tester.widget<AppAnimatedVisibility>(
        find
            .ancestor(
              of: find.text(text),
              matching: find.byType(AppAnimatedVisibility),
            )
            .first,
      );

  testWidgets(
    'requisitos en vivo, confirmación discreta y reaparición al editar',
    (tester) async {
      await mostrar(tester, const RegisterPage());
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      await escribir(tester, 2, 'abcdefg1');
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      await escribir(tester, 2, 'abcdef1!');
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      await escribir(tester, 3, 'a');
      expect(
        aviso('Las contraseñas aún no coinciden', tester).visible,
        isFalse,
      );
      await escribir(tester, 3, 'abc');
      expect(aviso('Las contraseñas aún no coinciden', tester).visible, isTrue);
      expect(
        tester
            .widget<Text>(find.text('Las contraseñas aún no coinciden'))
            .style!
            .color,
        const Color(0xFF6B7280),
      );
      await escribir(tester, 3, 'abcdef1!');
      expect(aviso('Las contraseñas coinciden', tester).visible, isTrue);
      expect(
        tester
            .widget<Text>(find.text('Las contraseñas coinciden'))
            .style!
            .color,
        const Color(0xFF047857),
      );
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(aviso('Mínimo 8 caracteres', tester).visible, isFalse);
      expect(aviso('Las contraseñas coinciden', tester).visible, isFalse);
      await escribir(tester, 2, 'abcdef12');
      expect(aviso('Mínimo 8 caracteres', tester).visible, isTrue);
      expect(aviso('Las contraseñas aún no coinciden', tester).visible, isTrue);
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
      await escribir(tester, 2, '');
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    },
  );

  testWidgets('una edición rápida cancela la ocultación pendiente', (
    tester,
  ) async {
    await mostrar(tester, const RegisterPage());
    await escribir(tester, 2, 'abcdef1!');
    await escribir(tester, 3, 'abcdef1!');
    await escribir(tester, 3, 'abcdef');
    await tester.pump(const Duration(seconds: 2));
    expect(aviso('Mínimo 8 caracteres', tester).visible, isTrue);
    expect(aviso('Las contraseñas aún no coinciden', tester).visible, isTrue);
    await escribir(tester, 3, 'abcdef1!');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'el envío impide cada incumplimiento y acepta las tres reglas juntas',
    (tester) async {
      await mostrar(tester, const RegisterPage());
      await escribir(tester, 0, 'Estudiante');
      await escribir(tester, 1, 'estudiante@example.com');
      for (final password in ['abcde1!', 'abcdefgh!', 'abcdefg1']) {
        await escribir(tester, 2, password);
        await escribir(tester, 3, password);
        await enviar(tester);
        expect(host.registros, isEmpty);
        expect(
          tester
              .widget<AuthStatusMessage>(find.byType(AuthStatusMessage))
              .message,
          contains('8 caracteres, 1 número y 1 carácter especial'),
        );
      }
      await escribir(tester, 2, 'abcdef1!');
      await escribir(tester, 3, 'abcdef2!');
      await enviar(tester);
      expect(host.registros, isEmpty);
      expect(
        tester
            .widget<AuthStatusMessage>(find.byType(AuthStatusMessage))
            .message,
        'Las contraseñas no coinciden.',
      );
      await escribir(tester, 3, 'abcdef1!');
      await enviar(tester);
      expect(host.registros, hasLength(1));
      expect(host.registros.single.last, 'abcdef1!');
    },
  );

  testWidgets('Login envía contraseñas antiguas sin las nuevas restricciones', (
    tester,
  ) async {
    await mostrar(tester, const LoginPage());
    await escribir(tester, 0, 'estudiante@example.com');
    await escribir(tester, 1, 'abc');
    await enviar(tester);
    expect(host.iniciosDeSesion, hasLength(1));
    expect(host.iniciosDeSesion.single.last, 'abc');
    expect(find.text('Mínimo 8 caracteres'), findsNothing);
  });

  testWidgets('el registro muestra carga y bloquea envíos duplicados', (
    tester,
  ) async {
    await TranslationService.instance.changeLanguage(AppLanguage.en);
    await mostrar(tester, const RegisterPage(), ancho: 320, escalaTexto: 1.3);
    await escribir(tester, 0, 'Estudiante');
    await escribir(tester, 1, 'estudiante@example.com');
    await escribir(tester, 2, 'abcdef1!');
    await escribir(tester, 3, 'abcdef1!');
    final respuesta = Completer<void>();
    host.respuestaPendiente = respuesta.future;
    await tester.ensureVisible(find.byType(ElevatedButton));
    await tester.tap(find.byType(ElevatedButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Creating account...'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PasswordVisibilityButton>(
            find.byType(PasswordVisibilityButton).first,
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byType(ElevatedButton));
    expect(host.registros, hasLength(1));
    expect(tester.takeException(), isNull);
    respuesta.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('mostrar contraseña conserva el texto, selección y foco', (
    tester,
  ) async {
    await mostrar(tester, const LoginPage());
    await escribir(tester, 1, 'clave existente');
    final field = tester.widget<TextField>(find.byType(TextField).last);
    field.controller!.selection = const TextSelection.collapsed(offset: 4);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).last).obscureText,
      isFalse,
    );
    expect(field.controller!.text, 'clave existente');
    expect(field.controller!.selection.baseOffset, 4);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });

  for (final oscuro in [false, true]) {
    testWidgets(
      'registro estrecho, texto ampliado e idioma inglés; oscuro=$oscuro',
      (tester) async {
        await TranslationService.instance.changeLanguage(AppLanguage.en);
        await mostrar(
          tester,
          const RegisterPage(),
          oscuro: oscuro,
          ancho: 320,
          escalaTexto: 1.3,
        );
        await escribir(tester, 2, 'abcdef1!');
        await escribir(tester, 3, 'abcdef1!');
        expect(aviso('Passwords match', tester).visible, isTrue);
        expect(find.text('At least 1 special character'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      },
    );
  }
}
