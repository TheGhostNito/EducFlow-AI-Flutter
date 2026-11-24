import 'dart:async';

import 'package:eduflow_ai/services/theme_service.dart';
import 'package:eduflow_ai/services/time_format_service.dart';
import 'package:eduflow_ai/services/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'tema lento ignora doble toque y mantiene visible igual a persistido',
    () async {
      final pending = Completer<void>();
      final persisted = <String>[];
      final service = ThemeService.forTesting((value) async {
        persisted.add(value);
        await pending.future;
      });

      final first = service.setDarkMode(true);
      await service.setDarkMode(false);
      expect(service.themeMode, ThemeMode.dark);
      expect(persisted, ['dark']);
      pending.complete();
      await first;
      expect(service.themeMode, ThemeMode.dark);
      expect(persisted.last, 'dark');
    },
  );

  test('tema revierte de forma coherente si falla la persistencia', () async {
    final service = ThemeService.forTesting(
      (_) async => throw StateError('firestore'),
    );
    await expectLater(service.setDarkMode(true), throwsStateError);
    expect(service.themeMode, ThemeMode.light);
  });

  test(
    'idioma serializa interacciones rápidas y revierte ante error',
    () async {
      final pending = Completer<void>();
      final persisted = <String>[];
      final service = TranslationService.forTesting((value) async {
        persisted.add(value);
        await pending.future;
      });

      final first = service.changeLanguage(AppLanguage.en);
      await service.changeLanguage(AppLanguage.es);
      expect(service.currentLanguage, AppLanguage.en);
      expect(persisted, ['en']);
      pending.complete();
      await first;
      expect(persisted.last, service.currentLanguage.name);

      final failing = TranslationService.forTesting(
        (_) async => throw StateError('firestore'),
      );
      await expectLater(
        failing.changeLanguage(AppLanguage.en),
        throwsStateError,
      );
      expect(failing.currentLanguage, AppLanguage.es);
    },
  );

  test('formato horario serializa y revierte ante error', () async {
    final pending = Completer<void>();
    final persisted = <String>[];
    final service = TimeFormatService.forTesting((value) async {
      persisted.add(value);
      await pending.future;
    });

    final first = service.setPreference(TimeFormatPreference.h24);
    await service.setPreference(TimeFormatPreference.h12);
    expect(service.preference, TimeFormatPreference.h24);
    expect(persisted, ['24h']);
    pending.complete();
    await first;
    expect(persisted.last, '24h');

    final failing = TimeFormatService.forTesting(
      (_) async => throw StateError('firestore'),
    );
    await expectLater(
      failing.setPreference(TimeFormatPreference.h12),
      throwsStateError,
    );
    expect(failing.preference, TimeFormatPreference.system);
  });
}
