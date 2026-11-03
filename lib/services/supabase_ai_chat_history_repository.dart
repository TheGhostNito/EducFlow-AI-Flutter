import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ai_conversation.dart';
import 'ai_chat_crypto_gateway.dart';
import 'ai_chat_history_service.dart';

abstract interface class AiChatSqlDataSource {
  Future<List<Map<String, dynamic>>> listChats(String uid);
  Future<Map<String, dynamic>?> getChat(String uid, String chatId);
  Future<List<Map<String, dynamic>>> listMessages(String uid, String chatId);
  Future<Map<String, dynamic>?> getMessage(
    String uid,
    String chatId,
    String messageId,
  );
  Future<Map<String, dynamic>> createChat(
    String uid,
    String chatId,
    AiChatCipher title,
  );
  Future<Map<String, dynamic>> saveMessage({
    required String uid,
    required String chatId,
    required String messageId,
    required String role,
    required AiChatCipher content,
    required bool isError,
    String? clearErrorMessageId,
  });
  Future<Map<String, dynamic>> changeState(
    String uid,
    String chatId,
    String action,
    String operationId,
  );
  Future<void> deleteChat(String uid, String chatId);
}

/// Solo se usa al construir expresamente SupabaseAiChatHistoryRepository.
class SupabaseAiChatSqlDataSource implements AiChatSqlDataSource {
  SupabaseAiChatSqlDataSource([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const _chatColumns =
      'id,titulo_cifrado,titulo_nonce,titulo_auth_tag,algoritmo_cifrado,'
      'version_cifrado,creado_en,actualizado_en,ultimo_mensaje_en,'
      'ultima_salida_en,cantidad_mensajes,archivado,ultima_operacion_estado_id';
  static const _messageColumns =
      'id,chat_id,rol,contenido_cifrado,contenido_nonce,contenido_auth_tag,'
      'algoritmo_cifrado,version_cifrado,creado_en,es_error';

  Map<String, dynamic> _row(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  @override
  Future<List<Map<String, dynamic>>> listChats(String uid) async {
    final rows = await _client
        .from('chats')
        .select(_chatColumns)
        .eq('usuario_uid', uid)
        .order('actualizado_en', ascending: false);
    return (rows as List).map(_row).toList();
  }

  @override
  Future<Map<String, dynamic>?> getChat(String uid, String chatId) async {
    final row = await _client
        .from('chats')
        .select(_chatColumns)
        .eq('usuario_uid', uid)
        .eq('id', chatId)
        .maybeSingle();
    return row == null ? null : _row(row);
  }

  @override
  Future<List<Map<String, dynamic>>> listMessages(
    String uid,
    String chatId,
  ) async {
    final rows = await _client
        .from('mensajes_chat')
        .select(_messageColumns)
        .eq('usuario_uid', uid)
        .eq('chat_id', chatId)
        .order('creado_en')
        .order('id');
    return (rows as List).map(_row).toList();
  }

  @override
  Future<Map<String, dynamic>?> getMessage(
    String uid,
    String chatId,
    String messageId,
  ) async {
    final row = await _client
        .from('mensajes_chat')
        .select(_messageColumns)
        .eq('usuario_uid', uid)
        .eq('chat_id', chatId)
        .eq('id', messageId)
        .maybeSingle();
    return row == null ? null : _row(row);
  }

  @override
  Future<Map<String, dynamic>> createChat(
    String uid,
    String chatId,
    AiChatCipher title,
  ) async {
    final row = await _client.rpc(
      'crear_chat_ia',
      params: {
        'p_expected_uid': uid,
        'p_chat_id': chatId,
        'p_title': title.toRpcPayload(),
      },
    );
    return _row(row);
  }

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
    final row = await _client.rpc(
      'guardar_mensaje_chat_ia',
      params: {
        'p_expected_uid': uid,
        'p_chat_id': chatId,
        'p_message_id': messageId,
        'p_role': role,
        'p_content': content.toRpcPayload(),
        'p_is_error': isError,
        'p_clear_error_message_id': clearErrorMessageId,
      },
    );
    return _row(row);
  }

  @override
  Future<Map<String, dynamic>> changeState(
    String uid,
    String chatId,
    String action,
    String operationId,
  ) async {
    final row = await _client.rpc(
      'cambiar_estado_chat_ia',
      params: {
        'p_expected_uid': uid,
        'p_chat_id': chatId,
        'p_action': action,
        'p_operation_id': operationId,
      },
    );
    return _row(row);
  }

  @override
  Future<void> deleteChat(String uid, String chatId) async {
    await _client.rpc(
      'eliminar_chat_ia',
      params: {'p_expected_uid': uid, 'p_chat_id': chatId},
    );
  }
}

/// Repositorio compartido para el historial IA de la aplicación principal.
class SupabaseAiChatHistoryRepository implements AiChatHistoryRepository {
  SupabaseAiChatHistoryRepository({
    required AiChatSqlDataSource dataSource,
    required AiChatCryptoGateway crypto,
    required String? Function() uidProvider,
    DateTime Function()? clock,
    String Function()? idGenerator,
  }) : // Public injection names are part of the testable constructor API.
       // ignore: prefer_initializing_formals
       _dataSource = dataSource,
       // ignore: prefer_initializing_formals
       _crypto = crypto,
       // ignore: prefer_initializing_formals
       _uidProvider = uidProvider,
       _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? _newId;

  factory SupabaseAiChatHistoryRepository.production() =>
      SupabaseAiChatHistoryRepository(
        dataSource: SupabaseAiChatSqlDataSource(),
        crypto: SupabaseAiChatCryptoGateway(),
        uidProvider: () => FirebaseAuth.instance.currentUser?.uid,
      );

  static final SupabaseAiChatHistoryRepository instance =
      SupabaseAiChatHistoryRepository.production();

  static const resumeWindow = Duration(minutes: 30);
  static const unavailableTitle = 'Chat no disponible';
  static const unavailableMessage = 'Mensaje no disponible';

  final AiChatSqlDataSource _dataSource;
  final AiChatCryptoGateway _crypto;
  final String? Function() _uidProvider;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  static String _newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String _uid() {
    final uid = _uidProvider();
    if (uid == null || uid.isEmpty) throw StateError('Sesión no disponible.');
    return uid;
  }

  void _guard(String uid) {
    if (_uidProvider() != uid) throw StateError('La sesión cambió.');
  }

  void _validateId(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) {
      throw ArgumentError('Identificador de chat no válido.');
    }
  }

  DateTime _date(Object? value, [DateTime? fallback]) =>
      DateTime.tryParse(value?.toString() ?? '') ?? fallback ?? _clock();

  DateTime? _dateOrNull(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  Future<AiConversation> _conversation(
    String uid,
    Map<String, dynamic> row,
  ) async {
    final id = row['id'] as String;
    String title = unavailableTitle;
    if (row['titulo_cifrado'] == null &&
        row['titulo_nonce'] == null &&
        row['titulo_auth_tag'] == null) {
      title = 'Chat';
    } else {
      try {
        final cipher = AiChatCipher.fromSql(row, 'titulo');
        title = await _crypto.decryptTitle(uid, id, cipher);
      } on AiChatCryptoException catch (error) {
        if (!_isPermanentCryptoFailure(error)) rethrow;
      }
    }
    _guard(uid);
    final created = _date(row['creado_en']);
    final updated = _date(row['actualizado_en'], created);
    return AiConversation(
      id: id,
      title: title,
      createdAt: created,
      updatedAt: updated,
      lastMessageAt: _date(row['ultimo_mensaje_en'], updated),
      lastExitAt: _dateOrNull(row['ultima_salida_en']),
      messageCount: (row['cantidad_mensajes'] as num?)?.toInt() ?? 0,
      archived: row['archivado'] == true,
    );
  }

  Future<AiChatMessage> _message(
    String uid,
    String chatId,
    Map<String, dynamic> row,
  ) async {
    final id = row['id'] as String;
    final role = row['rol'] == 'assistant'
        ? AiChatRole.assistant
        : AiChatRole.user;
    String text;
    bool isError = row['es_error'] == true;
    try {
      final cipher = AiChatCipher.fromSql(row, 'contenido');
      text = await _crypto.decryptMessage(uid, chatId, id, role.name, cipher);
    } on AiChatCryptoException catch (error) {
      if (!_isPermanentCryptoFailure(error)) rethrow;
      text = unavailableMessage;
      isError =
          true; // AiConversationContext excluye errores del contexto Gemini.
    }
    _guard(uid);
    return AiChatMessage(
      id: id,
      role: role,
      text: text,
      createdAt: _date(row['creado_en']),
      isError: isError,
    );
  }

  bool _isPermanentCryptoFailure(AiChatCryptoException error) => const {
    'version_incompatible',
    'bytea_invalido',
    'parametros_invalidos',
    'payload_invalido',
    'descifrado_incompatible',
  }.contains(error.code);

  void _requireSameMessage(
    AiChatMessage message,
    AiChatRole role,
    String text,
    bool isError,
  ) {
    if (message.role != role ||
        message.isError != isError ||
        message.text != text) {
      throw StateError('El ID corresponde a otro mensaje.');
    }
  }

  Future<AiChatMessage> _confirmedMessage(
    String uid,
    String chatId,
    String id,
    AiChatRole role,
    String text,
    bool isError,
    String? clearErrorMessageId,
    Map<String, dynamic> row,
  ) async {
    final message = await _message(uid, chatId, row);
    _requireSameMessage(message, role, text, isError);
    if (clearErrorMessageId == null || isError) return message;
    // Reutiliza los bytes ya confirmados. La RPC borra el error en la misma
    // transacción y nunca reemplaza el ciphertext de la respuesta.
    try {
      await _dataSource.saveMessage(
        uid: uid,
        chatId: chatId,
        messageId: id,
        role: role.name,
        content: AiChatCipher.fromSql(row, 'contenido'),
        isError: false,
        clearErrorMessageId: clearErrorMessageId,
      );
      _guard(uid);
    } on PostgrestException {
      rethrow;
    } catch (_) {
      _guard(uid);
      final error = await _dataSource.getMessage(
        uid,
        chatId,
        clearErrorMessageId,
      );
      _guard(uid);
      if (error != null && error['es_error'] == true) {
        throw const AiChatUnconfirmedDataException();
      }
    }
    return message;
  }

  @override
  Future<List<AiConversation>> getConversations() async {
    final uid = _uid();
    final rows = await _dataSource.listChats(uid);
    _guard(uid);
    final conversations = <AiConversation>[];
    for (final row in rows) {
      conversations.add(await _conversation(uid, row));
    }
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  @override
  Future<AiConversation?> getConversationToResume() async {
    final uid = _uid();
    final active = (await getConversations())
        .where((chat) => !chat.archived && chat.title != unavailableTitle)
        .toList();
    _guard(uid);
    if (active.isEmpty) return null;
    final newest = active.first;
    for (final older in active.skip(1)) {
      await archiveConversation(older.id);
    }
    final elapsed = _clock().difference(
      newest.lastExitAt ?? newest.lastMessageAt,
    );
    if (elapsed >= resumeWindow) {
      await archiveConversation(newest.id);
      return null;
    }
    await markEntered(newest.id);
    return newest.copyWith(archived: false, clearLastExitAt: true);
  }

  @override
  Future<AiConversation> createConversation(
    String firstMessage, {
    String? conversationId,
  }) async {
    final uid = _uid();
    final id = conversationId ?? _idGenerator();
    _validateId(id);
    final existing = await _dataSource.getChat(uid, id);
    _guard(uid);
    if (existing != null) {
      final conversation = await _conversation(uid, existing);
      if (conversation.title == unavailableTitle) {
        throw const AiChatCryptoException('chat_existente_incompatible');
      }
      return conversation;
    }
    final title = await _crypto.encryptTitle(
      uid,
      id,
      _buildTitle(firstMessage),
    );
    _guard(uid);
    try {
      final row = await _dataSource.createChat(uid, id, title);
      _guard(uid);
      final conversation = await _conversation(uid, row);
      if (conversation.title == unavailableTitle) {
        throw const AiChatCryptoException('chat_existente_incompatible');
      }
      return conversation;
    } catch (_) {
      _guard(uid);
      final confirmed = await _dataSource.getChat(uid, id);
      _guard(uid);
      if (confirmed != null) {
        final conversation = await _conversation(uid, confirmed);
        if (conversation.title == unavailableTitle) {
          throw const AiChatCryptoException('chat_existente_incompatible');
        }
        return conversation;
      }
      throw const AiChatUnconfirmedDataException();
    }
  }

  @override
  Future<AiChatMessage> addMessage({
    required String chatId,
    required AiChatRole role,
    required String text,
    bool isError = false,
    String? messageId,
    String? clearErrorMessageId,
  }) async {
    final uid = _uid();
    final id = messageId ?? _idGenerator();
    _validateId(chatId);
    _validateId(id);
    if (clearErrorMessageId != null) _validateId(clearErrorMessageId);
    final clean = text.trim();
    if (clean.isEmpty) throw ArgumentError('El mensaje no puede estar vacío.');
    final existing = await _dataSource.getMessage(uid, chatId, id);
    _guard(uid);
    if (existing != null && !(isError && existing['es_error'] == true)) {
      return _confirmedMessage(
        uid,
        chatId,
        id,
        role,
        clean,
        isError,
        clearErrorMessageId,
        existing,
      );
    }
    final cipher = await _crypto.encryptMessage(
      uid,
      chatId,
      id,
      role.name,
      clean,
    );
    _guard(uid);
    try {
      final row = await _dataSource.saveMessage(
        uid: uid,
        chatId: chatId,
        messageId: id,
        role: role.name,
        content: cipher,
        isError: isError,
        clearErrorMessageId: clearErrorMessageId,
      );
      _guard(uid);
      final confirmed = await _message(uid, chatId, row);
      _requireSameMessage(confirmed, role, clean, isError);
      return confirmed;
    } catch (_) {
      _guard(uid);
      final confirmed = await _dataSource.getMessage(uid, chatId, id);
      _guard(uid);
      if (confirmed != null) {
        return _confirmedMessage(
          uid,
          chatId,
          id,
          role,
          clean,
          isError,
          clearErrorMessageId,
          confirmed,
        );
      }
      throw const AiChatUnconfirmedDataException();
    }
  }

  @override
  Future<List<AiChatMessage>> getMessages(String chatId) async {
    final uid = _uid();
    _validateId(chatId);
    final rows = await _dataSource.listMessages(uid, chatId);
    _guard(uid);
    final messages = <AiChatMessage>[];
    for (final row in rows) {
      messages.add(await _message(uid, chatId, row));
    }
    messages.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return messages;
  }

  Future<void> _changeState(String chatId, String action) async {
    final uid = _uid();
    _validateId(chatId);
    final operationId = _newId();
    _validateId(operationId);
    try {
      final row = await _dataSource.changeState(
        uid,
        chatId,
        action,
        operationId,
      );
      _guard(uid);
      if (row['ultima_operacion_estado_id'] != operationId) {
        throw const AiChatUnconfirmedDataException();
      }
    } on PostgrestException {
      rethrow;
    } catch (_) {
      _guard(uid);
      Map<String, dynamic>? row;
      try {
        row = await _dataSource.getChat(uid, chatId);
      } catch (_) {
        _guard(uid);
        throw const AiChatUnconfirmedDataException();
      }
      _guard(uid);
      if (row?['ultima_operacion_estado_id'] != operationId) {
        throw const AiChatUnconfirmedDataException();
      }
    }
  }

  @override
  Future<void> markExited(String chatId) => _changeState(chatId, 'exit');

  @override
  Future<void> markEntered(String chatId) => _changeState(chatId, 'enter');

  @override
  Future<void> archiveConversation(String chatId) =>
      _changeState(chatId, 'archive');

  @override
  Future<AiConversation> reactivateConversation(
    AiConversation conversation,
  ) async {
    await _changeState(conversation.id, 'reactivate');
    return conversation.copyWith(archived: false, clearLastExitAt: true);
  }

  @override
  Future<void> deleteConversation(String chatId) async {
    final uid = _uid();
    _validateId(chatId);
    await _dataSource.deleteChat(uid, chatId);
    _guard(uid);
  }

  String _buildTitle(String firstMessage) {
    var clean = firstMessage.replaceAll(RegExp(r'\s+'), ' ').trim();
    clean = clean
        .replaceFirst(RegExp(r'''^[¿¡"']+'''), '')
        .replaceFirst(RegExp(r'''[?!"']+$'''), '')
        .trim();
    if (clean.isEmpty) return 'Nuevo chat';
    if (clean.length > 54) clean = '${clean.substring(0, 51).trimRight()}...';
    return clean[0].toUpperCase() + clean.substring(1);
  }
}
