import 'dart:io';

import 'package:eduflow_ai/models/horario_ocr_result.dart';
import 'package:eduflow_ai/models/horario_importacion.dart';
import 'package:eduflow_ai/pages/schedule/horario_ocr_review_page.dart';
import 'package:eduflow_ai/services/horario_importacion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final year in [2024, 2025]) {
    testWidgets('acepta fechas por definir para el horario $year', (
      tester,
    ) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: HorarioOcrReviewPage(
            result: _portfolioResult(year: year, withPeriodDates: false),
            spanish: true,
          ),
        ),
      );

      expect(
        find.byKey(const Key('horario-review-period-dates-optional')),
        findsOneWidget,
      );
      expect(find.textContaining('Por definir'), findsAtLeastNWidgets(2));
      await tester.tap(find.byKey(const Key('horario-review-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('horario-review-errors')), findsNothing);
      expect(find.byKey(const Key('horario-review-summary')), findsOneWidget);
      expect(find.textContaining('Por definir — Por definir'), findsOneWidget);
      expect(find.textContaining('4 sesiones'), findsAtLeastNWidgets(1));
    });
  }

  test('valida límites opcionales e independientes del período', () {
    final start = DateTime(2025, 3, 1);
    final end = DateTime(2025, 7, 31);

    expect(HorarioOcrReviewPage.periodoValido(null, null), isTrue);
    expect(HorarioOcrReviewPage.periodoValido(start, null), isTrue);
    expect(HorarioOcrReviewPage.periodoValido(null, end), isTrue);
    expect(HorarioOcrReviewPage.periodoValido(start, end), isTrue);
    expect(HorarioOcrReviewPage.periodoValido(end, start), isFalse);

    expect(
      HorarioOcrReviewPage.sesionDentroDeLimites(
        DateTime(2025, 4, 18),
        start,
        null,
      ),
      isTrue,
    );
    expect(
      HorarioOcrReviewPage.sesionDentroDeLimites(
        DateTime(2025, 2, 28),
        start,
        null,
      ),
      isFalse,
    );
    expect(
      HorarioOcrReviewPage.sesionDentroDeLimites(
        DateTime(2025, 8, 1),
        null,
        end,
      ),
      isFalse,
    );
  });

  testWidgets(
    'conserva cuatro sesiones de Portafolio y refleja correcciones en resumen',
    (tester) async {
      await _setLargeSurface(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: HorarioOcrReviewPage(
            result: _portfolioResult(year: 2024, withPeriodDates: true),
            spanish: true,
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('horario-review-session-date-0-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('horario-review-session-date-0-3')),
        findsOneWidget,
      );
      expect(find.text('Sin bloques semanales.'), findsOneWidget);

      final name = find.byKey(const ValueKey('horario-review-subject-name-0'));
      await tester.enterText(name, 'Portafolio 3 revisado');
      await tester.pump();
      await tester.tap(find.byKey(const Key('horario-review-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('horario-review-summary')), findsOneWidget);
      expect(find.text('Portafolio 3 revisado'), findsWidgets);
      expect(find.textContaining('4 sesiones'), findsAtLeastNWidgets(1));
      expect(find.textContaining('0 bloques'), findsAtLeastNWidgets(1));
      expect(
        find.text('Validación local completada. No se guardó información.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('permite agregar y quitar tipos de ocurrencia por separado', (
    tester,
  ) async {
    await _setLargeSurface(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: HorarioOcrReviewPage(
          result: _portfolioResult(year: 2024, withPeriodDates: true),
          spanish: true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('horario-review-session-date-0-3')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('horario-review-add-block-0')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('horario-review-block-day-0-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('horario-review-session-date-0-3')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('horario-review-remove-block-0-0')),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('horario-review-block-day-0-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('horario-review-session-date-0-3')),
      findsOneWidget,
    );
  });

  testWidgets('confirma una propuesta completa mediante una sola operación', (
    tester,
  ) async {
    await _setLargeSurface(tester);
    final gateway = _FakeImportGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: HorarioOcrReviewPage(
          result: _portfolioResult(year: 2025, withPeriodDates: false),
          spanish: true,
          documentHash: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sourceName: 'horario-2025.pdf',
          importacionGateway: gateway,
          writesEnabled: true,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('horario-review-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-review-save-import')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('horario-review-confirm-save')));
    await tester.pumpAndSettle();

    expect(gateway.confirmCalls, 1);
    expect(gateway.lastProposal?.periodo.fechaInicio, isNull);
    expect(gateway.lastProposal?.periodo.fechaFin, isNull);
    expect(gateway.lastProposal?.asignaturas, hasLength(1));
    expect(gateway.lastProposal?.asignaturas.single.sesiones, hasLength(4));
    expect(
      gateway.lastProposal?.asignaturas.single.asignatura.horario,
      isEmpty,
    );
    expect(find.text('Horario guardado'), findsOneWidget);
  });

  test('la revisión no depende de servicios de persistencia', () {
    final source = File('lib/pages/schedule/horario_ocr_review_page.dart')
        .readAsStringSync();

    expect(source, isNot(contains('supabase_flutter')));
    expect(source, isNot(contains('Supabase.instance')));
    expect(source, isNot(contains('AsignaturasService')));
    expect(source, isNot(contains('PeriodosAcademicosService')));
    expect(source, isNot(contains('SesionesClaseService')));
  });
}

class _FakeImportGateway implements HorarioImportacionGateway {
  int confirmCalls = 0;
  HorarioImportacionPropuesta? lastProposal;

  @override
  Future<HorarioImportacionResultado> confirmar(
    HorarioImportacionPropuesta propuesta,
  ) async {
    confirmCalls++;
    lastProposal = propuesta;
    return const HorarioImportacionResultado(
      importacionId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      periodoAcademicoId: 'horario-periodo-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      asignaturas: 1,
      bloques: 0,
      sesiones: 4,
      yaExistia: false,
    );
  }

  @override
  Future<HorarioImportacionEliminada> eliminar(String importacionId) {
    throw UnimplementedError();
  }

  @override
  Future<List<HorarioImportacionRegistro>> listar() {
    throw UnimplementedError();
  }

  @override
  Future<List<String>> obtenerAsignaturaIds(String importacionId) async =>
      const [];
}

Future<void> _setLargeSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1100, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

HorarioOcrResult _portfolioResult({
  required int year,
  required bool withPeriodDates,
}) {
  final number = year == 2024 ? 3 : 5;
  final dates = year == 2024
      ? [
          DateTime(2024, 3, 15),
          DateTime(2024, 4, 12),
          DateTime(2024, 5, 17),
          DateTime(2024, 6, 14),
        ]
      : [
          DateTime(2025, 3, 14),
          DateTime(2025, 4, 11),
          DateTime(2025, 5, 16),
          DateTime(2025, 6, 13),
        ];
  return HorarioOcrResult(
    documentHash: 'review-$year',
    pageCount: 2,
    period: HorarioOcrPeriod(
      year: year,
      semester: 1,
      startDate: withPeriodDates ? DateTime(year, 3, 1) : null,
      endDate: withPeriodDates ? DateTime(year, 7, 31) : null,
      evidence: const ['Primer semestre'],
      pendingReasons: const [],
    ),
    subjects: [
      HorarioOcrSubject(
        key: 'subject_1',
        name: 'Proceso de Portafolio $number',
        code: 'APY$number',
        section: '001D',
        professor: 'Docente de prueba',
        professorEmail: null,
        weeklyBlocks: const [],
        datedSessions: [
          for (final date in dates)
            HorarioOcrDatedSession(
              subjectKey: 'subject_1',
              date: date,
              startTime: '10:01',
              endTime: '11:20',
              room: year == 2024 ? 'LAB-1' : null,
              page: 2,
              evidence: const ['fecha específica'],
              pendingReasons: const [],
            ),
        ],
        sourcePages: const [1, 2],
        evidence: const ['Portafolio'],
        pendingReasons: const [],
      ),
    ],
    issues: const [],
    pendingReview: const [],
  );
}
