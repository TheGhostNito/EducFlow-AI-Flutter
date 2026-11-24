import 'dart:convert';

import 'package:eduflow_ai/models/ai_conversation.dart';
import 'package:eduflow_ai/services/ai_chat_crypto_gateway.dart';
import 'package:eduflow_ai/services/ai_chat_history_service.dart';
import 'package:eduflow_ai/services/ai_conversation_context.dart';
import 'package:eduflow_ai/services/supabase_ai_chat_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _now = '2026-10-28T12:00:00Z';

class _FakeCrypto implements AiChatCryptoGateway {
  void Function()? onEncryptTitle;
  int messageEncryptions = 0;
  AiChatCipher _seal(String scope, String text) => AiChatCipher(
    ciphertext: utf8.encode('$scope|$text'),
    nonce: List.filled(12, 1),
    authTag: List.filled(16, 2),
  );

  String _open(String scope, AiChatCipher cipher) {
    final value = utf8.decode(cipher.ciphertext);
    if (!value.startsWith('$scope|')) {
      throw const AiChatCryptoException('descifrado_incompatible');
    }
    return value.substring(scope.length + 1);
  }

  @override
  Future<AiChatCipher> encryptTitle(
    String uid,
    String chatId,
    String text,
  ) async {
    onEncryptTitle?.call();
    return _seal('$uid:$chatId:title', text);
  }

  @override
  Future<String> decryptTitle(
    String uid,
    String chatId,
    AiChatCipher cipher,
  ) async => _open('$uid:$chatId:title', cipher);

  @override
  Future<AiChatCipher> encryptMessage(
    String uid,
    String chatId,
    String messageId,
    String role,
    String text,
  ) async {
    messageEncryptions++;
    return _seal('$uid:$chatId:$messageId:$role', text);
  }

  @override
  Future<String> decryptMessage(
    String uid,
    String chatId,
    String messageId,
    String role,
    AiChatCipher cipher,
  ) async => _open('$uid:$chatId:$messageId:$role', cipher);
}

class _FakeSql implements AiChatSqlDataSource {
  _FakeSql(this.currentUid);
  final String? Function() currentUid;
  final chats = <String, Map<String, dynamic>>{};
  final messages = <String, Map<String, dynamic>>{};
  bool failAfterCreate = false;
  bool failBeforeMessage = false;
  bool failAfterMessage = false;
  bool failBeforeState = false;
  bool failAfterState = false;
  bool failReadChat = false;
  Object? definitiveStateError;
  int messageWrites = 0;

  String _key(String uid, String id) => '$uid/$id';
  String _messageKey(String uid, String chatId, String id) =>
      '$uid/$chatId/$id';

  Map<String, dynamic> _fields(String prefix, AiChatCipher cipher) {
    final payload = cipher.toRpcPayload();
    return {
      '${prefix}_cifrado': r'\x' + payload['ciphertext_hex'],
      '${prefix}_nonce': r'\x' + payload['nonce_hex'],
      '${prefix}_auth_tag': r'\x' + payload['auth_tag_hex'],
      'algoritmo_cifrado': AiChatCipher.algorithm,
      'version_cifrado': AiChatCipher.version,
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listChats(String uid) async => chats
      .entries
      .where((entry) => entry.key.startsWith('$uid/'))
      .map((entry) => Map<String, dynamic>.from(entry.value))
      .toList();

  @override
  Future<Map<String, dynamic>?> getChat(String uid, String chatId) async {
    if (failReadChat) throw StateError('lectura sin conexión');
    return chats[_key(uid, chatId)];
  }

  @override
  Future<Map<String, dynamic>> createChat(
    String uid,
    String chatId,
    AiChatCipher title,
  ) async {
    if (currentUid() != uid) throw StateError('UID cambiado');
    final prior = chats[_key(uid, chatId)];
    if (prior != null) return prior;
    for (final entry in chats.entries) {
      if (entry.key.startsWith('$uid/') && entry.value['archivado'] == false) {
        entry.value['archivado'] = true;
        entry.value['ultima_salida_en'] = _now;
      }
    }
    final row = chats.putIfAbsent(
      _key(uid, chatId),
      () => {
        'id': chatId,
        ..._fields('titulo', title),
        'creado_en': _now,
        'actualizado_en': _now,
        'ultimo_mensaje_en': _now,
        'ultima_salida_en': null,
        'cantidad_mensajes': 0,
        'archivado': false,
      },
    );
    if (failAfterCreate) {
      failAfterCreate = false;
      throw StateError('respuesta perdida');
    }
    return row;
  }

  @override
  Future<List<Map<String, dynamic>>> listMessages(
    String uid,
    String chatId,
  ) async => messages.entries
      .where((entry) => entry.key.startsWith('$uid/$chatId/'))
      .map((entry) => Map<String, dynamic>.from(entry.value))
      .toList();

  @override
  Future<Map<String, dynamic>?> getMessage(
    String uid,
    String chatId,
    String messageId,
  ) async => messages[_messageKey(uid, chatId, messageId)];

  @override
  Future<Map<String, dynamic>> saveMessage({
    required String uid,
    required String chatId,
    required String messageId,
    required String role,
    required AiChatCipher content,
    required bool isError,
    String? clearErrorMessageId,
  }) async {
    if (failBeforeMessage) throw StateError('sin conexión');
    if (currentUid() != uid) throw StateError('UID cambiado');
    final key = _messageKey(uid, chatId, messageId);
    final existing = messages[key];
    if (existing != null && !(isError && existing['es_error'] == true)) {
      if (clearErrorMessageId != null) {
        final errorKey = _messageKey(uid, chatId, clearErrorMessageId);
        if (messages[errorKey]?['es_error'] == true) {
          messages.remove(errorKey);
          chats[_key(uid, chatId)]!['cantidad_mensajes']--;
        }
      }
      return existing;
    }
    if (existing == null && clearErrorMessageId != null) {
      final errorKey = _messageKey(uid, chatId, clearErrorMessageId);
      if (messages[errorKey]?['es_error'] == true) {
        messages.remove(errorKey);
        chats[_key(uid, chatId)]!['cantidad_mensajes']--;
      }
    }
    final row = {
      'id': messageId,
      'chat_id': chatId,
      'rol': role,
      ..._fields('contenido', content),
      'creado_en': _now,
      'es_error': isError,
    };
    messages[key] = row;
    if (existing == null) chats[_key(uid, chatId)]!['cantidad_mensajes']++;
    messageWrites++;
    if (failAfterMessage) {
      failAfterMessage = false;
      throw StateError('respuesta perdida');
    }
    return row;
  }

  @override
  Future<Map<String, dynamic>> changeState(
    String uid,
    String chatId,
    String action,
    String operationId,
  ) async {
    if (definitiveStateError != null) throw definitiveStateError!;
    if (failBeforeState) throw StateError('fallo antes de escribir');
    if (currentUid() != uid) throw StateError('UID cambiado');
    final row = chats[_key(uid, chatId)]!;
    if (row['ultima_operacion_estado_id'] == operationId) return row;
    if (action == 'enter' || action == 'reactivate') {
      for (final entry in chats.entries) {
        if (entry.key.startsWith('$uid/') &&
            entry.key != _key(uid, chatId) &&
            entry.value['archivado'] == false) {
          entry.value['archivado'] = true;
          entry.value['ultima_salida_en'] = _now;
        }
      }
    }
    if (action == 'archive') row['archivado'] = true;
    if (action == 'enter' || action == 'reactivate') {
      row['archivado'] = false;
      row['ultima_salida_en'] = null;
    } else {
      row['ultima_salida_en'] = _now;
    }
    row['ultima_operacion_estado_id'] = operationId;
    if (failAfterState) {
      failAfterState = false;
      throw StateError('respuesta perdida');
    }
    return row;
  }

  @override
  Future<void> deleteChat(String uid, String chatId) async {
    if (currentUid() != uid) throw StateError('UID cambiado');
    chats.remove(_key(uid, chatId));
    messages.removeWhere((key, _) => key.startsWith('$uid/$chatId/'));
  }
}

void main() {
  late String? uid;
  late _FakeSql sql;
  late _FakeCrypto crypto;
  late SupabaseAiChatHistoryRepository repository;

  setUp(() {
    uid = 'usuarioA';
    sql = _FakeSql(() => uid);
    crypto = _FakeCrypto();
    repository = SupabaseAiChatHistoryRepository(
      dataSource: sql,
      crypto: crypto,
      uidProvider: () => uid,
      clock: () => DateTime.parse(_now),
      idGenerator: () => 'idGenerado',
    );
  });

  test('bytea hex, Base64 y longitudes coinciden con el contrato v1', () {
    final cipher = AiChatCipher(
      ciphertext: [0, 15, 255],
      nonce: List.filled(12, 1),
      authTag: List.filled(16, 2),
    );
    final row = {...sql._fields('contenido', cipher)};
    final restored = AiChatCipher.fromSql(row, 'contenido');
    expect(restored.ciphertext, cipher.ciphertext);
    expect(restored.toFunctionPayload()['ciphertext'], 'AA//');
    expect(row['contenido_cifrado'], r'\x000fff');
  });

  test('creación y reintento con el mismo ID no duplican el chat', () async {
    sql.failAfterCreate = true;
    final first = await repository.createConversation(
      'Hola',
      conversationId: 'chatA',
    );
    final second = await repository.createConversation(
      'Otro',
      conversationId: 'chatA',
    );
    expect(first.id, second.id);
    expect(first.title, 'Hola');
    expect(sql.chats.length, 1);
  });

  test('mensaje confirmado tras timeout y reintento no se duplican', () async {
    await repository.createConversation('Hola', conversationId: 'chatA');
    sql.failAfterMessage = true;
    final first = await repository.addMessage(
      chatId: 'chatA',
      role: AiChatRole.user,
      text: 'Texto ficticio',
      messageId: 'msgA',
    );
    final retry = await repository.addMessage(
      chatId: 'chatA',
      role: AiChatRole.user,
      text: 'Texto ficticio',
      messageId: 'msgA',
    );
    expect(first.text, retry.text);
    expect(sql.messageWrites, 1);
    expect(sql.chats['usuarioA/chatA']!['cantidad_mensajes'], 1);
  });

  test('sin conexión y sin confirmación conserva error recuperable', () async {
    await repository.createConversation('Hola', conversationId: 'chatA');
    sql.failBeforeMessage = true;
    await expectLater(
      repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.user,
        text: 'Texto ficticio',
        messageId: 'msgA',
      ),
      throwsA(isA<AiChatUnconfirmedDataException>()),
    );
    expect(sql.messages, isEmpty);
  });

  test('error de IA se reemplaza sin aumentar el contador', () async {
    await repository.createConversation('Hola', conversationId: 'chatA');
    await repository.addMessage(
      chatId: 'chatA',
      role: AiChatRole.assistant,
      text: 'Error ficticio',
      isError: true,
      messageId: 'errorA',
    );
    await repository.addMessage(
      chatId: 'chatA',
      role: AiChatRole.assistant,
      text: 'Respuesta ficticia',
      messageId: 'msgB',
      clearErrorMessageId: 'errorA',
    );
    expect(sql.messages.length, 1);
    expect(sql.chats['usuarioA/chatA']!['cantidad_mensajes'], 1);
  });

  test(
    'I1: timeout, respuesta confirmada, error y reintento limpia error',
    () async {
      await repository.createConversation('Hola', conversationId: 'chatA');
      final confirmedCipher = await crypto.encryptMessage(
        'usuarioA',
        'chatA',
        'respuestaA',
        'assistant',
        'Respuesta ficticia',
      );
      // La respuesta se confirmó después de que el cliente agotó su espera.
      await sql.saveMessage(
        uid: 'usuarioA',
        chatId: 'chatA',
        messageId: 'respuestaA',
        role: 'assistant',
        content: confirmedCipher,
        isError: false,
      );
      await repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.assistant,
        text: 'Error ficticio',
        isError: true,
        messageId: 'errorA',
      );
      final originalCiphertext =
          sql.messages['usuarioA/chatA/respuestaA']!['contenido_cifrado'];
      final encryptionsBeforeRetry = crypto.messageEncryptions;
      await repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.assistant,
        text: 'Respuesta ficticia',
        messageId: 'respuestaA',
        clearErrorMessageId: 'errorA',
      );
      expect(sql.messages.keys, contains('usuarioA/chatA/respuestaA'));
      expect(sql.messages.keys, isNot(contains('usuarioA/chatA/errorA')));
      expect(sql.chats['usuarioA/chatA']!['cantidad_mensajes'], 1);
      expect(
        sql.messages['usuarioA/chatA/respuestaA']!['contenido_cifrado'],
        originalCiphertext,
      );
      expect(crypto.messageEncryptions, encryptionsBeforeRetry);
    },
  );

  test('I2: enter de chat archivado conserva uno solo activo', () async {
    await repository.createConversation('Uno', conversationId: 'chatA');
    await repository.createConversation('Dos', conversationId: 'chatB');
    await repository.markEntered('chatA');
    expect(
      sql.chats.values.where((row) => row['archivado'] == false).length,
      1,
    );
    expect(sql.chats['usuarioA/chatA']!['archivado'], false);
  });

  test('I2: create y reactivate concurrentes dejan un solo activo', () async {
    final chats = await Future.wait([
      repository.createConversation('Uno', conversationId: 'chatA'),
      repository.createConversation('Dos', conversationId: 'chatB'),
    ]);
    expect(
      sql.chats.values.where((row) => row['archivado'] == false).length,
      1,
    );
    await Future.wait([
      repository.reactivateConversation(chats.first),
      repository.createConversation('Tres', conversationId: 'chatC'),
    ]);
    expect(
      sql.chats.values.where((row) => row['archivado'] == false).length,
      1,
    );
    await repository.reactivateConversation(chats.last);
    expect(sql.chats['usuarioA/chatB']!['archivado'], false);
    expect(
      sql.chats.values.where((row) => row['archivado'] == false).length,
      1,
    );
  });

  test('I3: fallo previo no confirma archive ya archivado', () async {
    await repository.createConversation('Uno', conversationId: 'chatA');
    sql.chats['usuarioA/chatA']!['archivado'] = true;
    sql.failBeforeState = true;
    await expectLater(
      repository.archiveConversation('chatA'),
      throwsA(isA<AiChatUnconfirmedDataException>()),
    );
  });

  test(
    'I3: fallo previo no confirma exit con fecha de salida antigua',
    () async {
      await repository.createConversation('Uno', conversationId: 'chatA');
      sql.chats['usuarioA/chatA']!['ultima_salida_en'] = '2026-10-28T11:00:00Z';
      sql.failBeforeState = true;
      await expectLater(
        repository.markExited('chatA'),
        throwsA(isA<AiChatUnconfirmedDataException>()),
      );
    },
  );

  test(
    'I3: respuesta perdida después de escribir confirma por operación',
    () async {
      await repository.createConversation('Uno', conversationId: 'chatA');
      sql.failAfterState = true;
      await repository.markExited('chatA');
      expect(
        sql.chats['usuarioA/chatA']!['ultima_operacion_estado_id'],
        isNotNull,
      );
      expect(sql.chats['usuarioA/chatA']!['ultima_salida_en'], _now);
    },
  );

  test('I3: error SQL definitivo conserva su causa', () async {
    await repository.createConversation('Uno', conversationId: 'chatA');
    sql.definitiveStateError = const PostgrestException(
      message: 'permiso denegado',
      code: '42501',
    );
    await expectLater(
      repository.archiveConversation('chatA'),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('I3: respuesta y lectura perdidas quedan sin confirmar', () async {
    await repository.createConversation('Uno', conversationId: 'chatA');
    sql.failBeforeState = true;
    sql.failReadChat = true;
    await expectLater(
      repository.markExited('chatA'),
      throwsA(isA<AiChatUnconfirmedDataException>()),
    );
  });

  test('dos escrituras concurrentes del mismo ID dejan un mensaje', () async {
    await repository.createConversation('Hola', conversationId: 'chatA');
    await Future.wait([
      repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.user,
        text: 'Texto ficticio',
        messageId: 'msgA',
      ),
      repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.user,
        text: 'Texto ficticio',
        messageId: 'msgA',
      ),
    ]);
    expect(sql.messages.length, 1);
    expect(sql.chats['usuarioA/chatA']!['cantidad_mensajes'], 1);
  });

  test('cambio de usuario no muestra conversaciones de otro UID', () async {
    await repository.createConversation('Hola', conversationId: 'chatA');
    uid = 'usuarioB';
    expect(await repository.getConversations(), isEmpty);
    uid = 'usuarioA';
    expect((await repository.getConversations()).length, 1);
  });

  test(
    'nueva instancia recupera título y mensajes del mismo usuario',
    () async {
      await repository.createConversation('Hola', conversationId: 'chatA');
      await repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.user,
        text: 'Texto ficticio',
        messageId: 'msgA',
      );
      final newSession = SupabaseAiChatHistoryRepository(
        dataSource: sql,
        crypto: _FakeCrypto(),
        uidProvider: () => uid,
        clock: () => DateTime.parse(_now),
      );
      expect((await newSession.getConversations()).single.title, 'Hola');
      expect(
        (await newSession.getMessages('chatA')).single.text,
        'Texto ficticio',
      );
    },
  );

  test('cambio de usuario durante cifrado impide la escritura', () async {
    crypto.onEncryptTitle = () => uid = 'usuarioB';
    await expectLater(
      repository.createConversation('Hola', conversationId: 'chatA'),
      throwsStateError,
    );
    expect(sql.chats, isEmpty);
  });

  test(
    'reintento con ID de otro mensaje no acepta contenido distinto',
    () async {
      await repository.createConversation('Hola', conversationId: 'chatA');
      await repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.user,
        text: 'Uno',
        messageId: 'msgA',
      );
      await expectLater(
        repository.addMessage(
          chatId: 'chatA',
          role: AiChatRole.user,
          text: 'Dos',
          messageId: 'msgA',
        ),
        throwsStateError,
      );
      expect(sql.messageWrites, 1);
    },
  );

  test('fila incompatible no bloquea el resto del historial', () async {
    await repository.createConversation('Hola', conversationId: 'chatA');
    final bad = Map<String, dynamic>.from(sql.chats['usuarioA/chatA']!);
    bad['id'] = 'chatAntiguo';
    bad['version_cifrado'] = 99;
    sql.chats['usuarioA/chatAntiguo'] = bad;
    final rows = await repository.getConversations();
    expect(rows.length, 2);
    expect(
      rows.any(
        (row) => row.title == SupabaseAiChatHistoryRepository.unavailableTitle,
      ),
      isTrue,
    );
    expect(rows.any((row) => row.title == 'Hola'), isTrue);
  });

  test(
    'mensaje incompatible no bloquea otros mensajes ni el contexto',
    () async {
      await repository.createConversation('Hola', conversationId: 'chatA');
      await repository.addMessage(
        chatId: 'chatA',
        role: AiChatRole.user,
        text: 'Mensaje válido',
        messageId: 'msgA',
      );
      final bad = Map<String, dynamic>.from(
        sql.messages['usuarioA/chatA/msgA']!,
      );
      bad['id'] = 'msgB';
      bad['version_cifrado'] = 99;
      sql.messages['usuarioA/chatA/msgB'] = bad;
      final messages = await repository.getMessages('chatA');
      expect(messages.length, 2);
      expect(
        messages.any((message) => message.text == 'Mensaje válido'),
        isTrue,
      );
      expect(
        messages.any(
          (message) =>
              message.text ==
                  SupabaseAiChatHistoryRepository.unavailableMessage &&
              message.isError,
        ),
        isTrue,
      );
      expect(
        AiConversationContext.completedHistory(
          messages,
          currentMessage: 'Consulta nueva',
        ),
        isEmpty,
      );
    },
  );

  test('reanudación conserva la ventana de 30 minutos', () async {
    await repository.createConversation('Hola', conversationId: 'chatA');
    expect((await repository.getConversationToResume())?.id, 'chatA');
    sql.chats['usuarioA/chatA']!['ultimo_mensaje_en'] = '2026-10-28T11:20:00Z';
    expect(await repository.getConversationToResume(), isNull);
    expect(sql.chats['usuarioA/chatA']!['archivado'], isTrue);
  });
}
