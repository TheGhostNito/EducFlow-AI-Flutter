import 'dart:io';

import 'package:eduflow_ai/models/asignatura.dart';
import 'package:eduflow_ai/models/horario_importacion.dart';
import 'package:eduflow_ai/models/periodo_academico.dart';
import 'package:eduflow_ai/services/horario_importacion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const importId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('serializa una importación completa con fechas de período nulas', () {
    const codec = HorarioImportacionSqlCodec();
    final payload = codec.propuesta(_proposal(hash));

    expect(payload['importacion_id'], importId);
    expect(payload['document_hash'], hash);
    final period = payload['periodo'] as Map<String, dynamic>;
    expect(period['fecha_inicio'], isNull);
    expect(period['fecha_fin'], isNull);
    final subjects = payload['asignaturas'] as List;
    expect(subjects, hasLength(2));
    expect((subjects.first as Map)['bloques'], hasLength(1));
    final portfolio = subjects.last as Map;
    expect(portfolio['bloques'], isEmpty);
    expect(portfolio['sesiones'], hasLength(4));
    expect(
      (portfolio['sesiones'] as List).every(
        (value) => (value as Map)['sala'] == null,
      ),
      isTrue,
      reason: 'Portafolio 5 no recibe una sala sin evidencia inequívoca.',
    );
  });

  test('serializa metadatos del original sin incluir sus bytes', () {
    const codec = HorarioImportacionSqlCodec();
    final payload = codec.propuesta(
      _proposal(
        hash,
        document: const HorarioDocumentoOriginal(
          path: 'uid-a/$importId/123.pdf',
          nombre: 'Horario 2025.pdf',
          mimeType: 'application/pdf',
          sizeBytes: 2048,
        ),
      ),
    );

    expect(payload['documento_original'], {
      'path': 'uid-a/$importId/123.pdf',
      'nombre': 'Horario 2025.pdf',
      'mime': 'application/pdf',
      'size': 2048,
    });
    expect(payload.toString(), isNot(contains('bytes')));
  });

  test('usa el UID autenticado y no repite llamadas tras un fallo', () async {
    final source = _FakeDataSource()..failConfirmation = true;
    final service = HorarioImportacionService(
      dataSource: source,
      uidProvider: () => 'uid-a',
    );

    await expectLater(service.confirmar(_proposal(hash)), throwsStateError);
    expect(source.confirmCalls, 1);
    expect(source.lastUid, 'uid-a');
    expect(source.savedPayloads, isEmpty);
  });

  test('la repetición devuelve la misma importación sin duplicarla', () async {
    final source = _FakeDataSource();
    final service = HorarioImportacionService(
      dataSource: source,
      uidProvider: () => 'uid-a',
    );

    final first = await service.confirmar(_proposal(hash));
    final second = await service.confirmar(_proposal(hash));

    expect(first.yaExistia, isFalse);
    expect(second.yaExistia, isTrue);
    expect(source.savedPayloads, hasLength(1));
    expect(await service.obtenerAsignaturaIds(importId), [
      'horario-$importId-a-1',
      'horario-$importId-a-2',
    ]);
  });

  test('el borrado se limita al UID y a la importación seleccionada', () async {
    final source = _FakeDataSource();
    final serviceA = HorarioImportacionService(
      dataSource: source,
      uidProvider: () => 'uid-a',
    );
    final serviceB = HorarioImportacionService(
      dataSource: source,
      uidProvider: () => 'uid-b',
    );
    await serviceA.confirmar(_proposal(hash));
    await serviceB.confirmar(
      _proposal(
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    );

    final deleted = await serviceA.eliminar(importId);

    expect(deleted.asignaturasEliminadas, 2);
    expect(await serviceA.listar(), isEmpty);
    expect(await serviceB.listar(), hasLength(1));
  });

  test(
    'la migración define atomicidad, idempotencia, RLS y borrado exacto',
    () {
      final sql = File(
        'supabase/migrations/202611220001_importaciones_horario_atomicas.sql',
      ).readAsStringSync();

      expect(
        sql.trimLeft(),
        startsWith('-- Confirmación y eliminación atómicas'),
      );
      expect(sql, contains('begin;'));
      expect(sql, contains('commit;'));
      expect(sql, contains('unique (usuario_uid, document_hash)'));
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(sql, contains("'ya_existia', true"));
      expect(sql, contains('asignatura_academica_preexistente'));
      expect(sql, contains('importacion_horario_asignaturas'));
      expect(sql, contains('id = any(v_ids)'));
      expect(sql, contains('importacion_tiene_evaluaciones'));
      expect(sql, contains('importacion_tiene_tareas'));
      expect(sql, contains('importacion_tiene_relaciones'));
      expect(sql, contains('horario_importacion_autorizaciones'));
      expect(sql, contains('importacion_horario_no_autorizada'));
      expect(sql, contains('on delete restrict'));
      expect(sql, contains('desvinculacion_importacion_incompleta'));
      expect(sql, contains('importacion_tiene_dependencias'));
      expect(sql, contains('ocurrencias_importacion_modificadas'));
      expect(sql, contains("then 'registrada'"));
      expect(sql, contains('enable row level security'));
      expect(sql, contains('is_educflow_firebase_user'));
      expect(sql, contains("set search_path = ''"));
      expect(
        sql,
        contains(
          'on table public.horario_importacion_autorizaciones to service_role',
        ),
      );
      expect(sql, isNot(contains('educflow.eliminando_importacion_horario')));
      expect(sql, isNot(contains('truncate')));
      expect(sql, isNot(contains('drop table')));
    },
  );

  test(
    'la migración del original mantiene bucket privado y limpieza segura',
    () {
      final sql = File(
        'supabase/migrations/202611230001_documentos_originales_horario.sql',
      ).readAsStringSync();

      expect(sql, contains("'horarios-originales'"));
      expect(sql, contains("'application/pdf'"));
      expect(sql, contains('10485760'));
      expect(sql, contains('public.is_educflow_firebase_user()'));
      expect(sql, contains('public.current_firebase_uid()'));
      expect(sql, contains('public.uid_importacion_horario_autorizado()'));
      expect(sql, contains('confirmar_importacion_horario_con_documento'));
      expect(sql, contains('asociar_documento_importacion_horario'));
      expect(sql, contains('horario_documentos_limpieza'));
      expect(sql, contains('documento_requiere_eliminacion_segura'));
      expect(sql, contains('importaciones_horario_proteger_documento'));
      expect(sql, contains('archivo_storage_aun_existe'));
      expect(sql, contains('select 1 from storage.objects'));
      expect(
        sql,
        contains(
          'grant execute on function public.confirmar_limpieza_documento_horario(text) to service_role',
        ),
      );
      expect(sql, isNot(contains('horario_documento_delete_own')));
      expect(
        sql,
        isNot(
          contains(
            'grant execute on function public.confirmar_limpieza_documento_horario(text) to authenticated',
          ),
        ),
      );
      expect(sql, contains("set search_path = ''"));
      expect(sql, contains('to authenticated'));
      expect(sql, isNot(contains('service_role key')));
      expect(sql, isNot(contains('public = true')));
    },
  );
}

HorarioImportacionPropuesta _proposal(
  String hash, {
  HorarioDocumentoOriginal? document,
}) {
  final period = PeriodoAcademico(
    id: 'pendiente',
    anio: 2025,
    tipo: TipoPeriodoAcademico.semestre,
    numero: 1,
    nombre: 'Semestre 1 de 2025',
  );
  return HorarioImportacionPropuesta(
    documentHash: hash,
    nombreDocumento: 'horario-2025.pdf',
    periodo: period,
    asignaturas: [
      HorarioImportacionAsignatura(
        asignatura: const Asignatura(
          id: 'pendiente_1',
          nombre: 'Programación',
          estado: EstadoAsignatura.enCurso,
          origen: OrigenAsignatura.horario,
          sigla: 'PGY1234',
          seccion: '001D',
          anioAcademico: 2025,
          periodoAcademicoId: 'pendiente',
          horario: [
            BloqueHorario(
              dia: DiaSemana.lunes,
              horaInicio: '08:30',
              horaFin: '10:00',
              sala: 'A-101',
            ),
          ],
        ),
        sesiones: const [],
      ),
      HorarioImportacionAsignatura(
        asignatura: const Asignatura(
          id: 'pendiente_2',
          nombre: 'Proceso de Portafolio 5',
          estado: EstadoAsignatura.enCurso,
          origen: OrigenAsignatura.horario,
          sigla: 'APY5001',
          seccion: '001D',
          anioAcademico: 2025,
          periodoAcademicoId: 'pendiente',
        ),
        sesiones: [
          for (final month in [3, 4, 5, 6])
            HorarioImportacionSesion(
              fecha: DateTime(2025, month, 14),
              horaInicio: '18:30',
              horaFin: '20:00',
            ),
        ],
      ),
    ],
    documentoOriginal: document,
  );
}

class _FakeDataSource implements HorarioImportacionDataSource {
  final Map<String, Map<String, Map<String, dynamic>>> savedPayloads = {};
  bool failConfirmation = false;
  int confirmCalls = 0;
  String? lastUid;

  @override
  Future<Map<String, dynamic>> confirmar(
    String uid,
    Map<String, dynamic> payload,
  ) async {
    confirmCalls++;
    lastUid = uid;
    if (failConfirmation) throw StateError('fallo simulado');
    final byUid = savedPayloads.putIfAbsent(uid, () => {});
    final hash = payload['document_hash'] as String;
    final existed = byUid.containsKey(hash);
    byUid.putIfAbsent(hash, () => payload);
    final subjects = payload['asignaturas'] as List;
    return {
      'importacion_id': payload['importacion_id'],
      'periodo_academico_id': 'horario-periodo-${payload['importacion_id']}',
      'asignaturas': subjects.length,
      'bloques': subjects.fold<int>(
        0,
        (sum, value) => sum + ((value as Map)['bloques'] as List).length,
      ),
      'sesiones': subjects.fold<int>(
        0,
        (sum, value) => sum + ((value as Map)['sesiones'] as List).length,
      ),
      'ya_existia': existed,
    };
  }

  @override
  Future<Map<String, dynamic>> eliminar(
    String uid,
    String importacionId,
  ) async {
    lastUid = uid;
    final byUid = savedPayloads[uid] ?? {};
    final entry = byUid.entries.singleWhere(
      (value) => value.value['importacion_id'] == importacionId,
    );
    final subjects = entry.value['asignaturas'] as List;
    byUid.remove(entry.key);
    return {
      'importacion_id': importacionId,
      'asignaturas_eliminadas': subjects.length,
      'periodo_eliminado': true,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listar(String uid) async {
    lastUid = uid;
    return [
      for (final payload in (savedPayloads[uid] ?? {}).values)
        {
          'id': payload['importacion_id'],
          'document_hash': payload['document_hash'],
          'nombre_documento': payload['nombre_documento'],
          'anio': (payload['periodo'] as Map)['anio'],
          'numero_periodo': (payload['periodo'] as Map)['numero'],
          'periodo_academico_id':
              'horario-periodo-${payload['importacion_id']}',
          'asignaturas': (payload['asignaturas'] as List).length,
          'bloques': 1,
          'sesiones': 4,
          'creada_en': '2026-11-22T10:00:00Z',
        },
    ];
  }

  @override
  Future<List<String>> obtenerAsignaturaIds(
    String uid,
    String importacionId,
  ) async {
    lastUid = uid;
    final payload = (savedPayloads[uid] ?? {}).values.singleWhere(
      (value) => value['importacion_id'] == importacionId,
    );
    final subjects = payload['asignaturas'] as List;
    return [
      for (var index = 0; index < subjects.length; index++)
        'horario-$importacionId-a-${index + 1}',
    ];
  }
}
