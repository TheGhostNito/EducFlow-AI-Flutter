import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/ai_conversation.dart';

class AiChatUnconfirmedDataException implements Exception {
  const AiChatUnconfirmedDataException();
}

abstract interface class AiChatHistoryRepository {
  Future<List<AiConversation>> getConversations();

  Future<void> deleteConversation(String chatId);

  Future<AiConversation?> getConversationToResume();

  Future<AiConversation> createConversation(
    String firstMessage, {
    String? conversationId,
  });

  Future<AiChatMessage> addMessage({
    required String chatId,
    required AiChatRole role,
    required String text,
    bool isError = false,
    String? messageId,
    String? clearErrorMessageId,
  });

  Future<List<AiChatMessage>> getMessages(String chatId);

  Future<void> markExited(String chatId);

  Future<void> markEntered(String chatId);

  Future<void> archiveConversation(String chatId);

  Future<AiConversation> reactivateConversation(AiConversation conversation);
}

class AiChatHistoryService implements AiChatHistoryRepository {
  AiChatHistoryService._();

  static final AiChatHistoryService instance = AiChatHistoryService._();

  static const Duration resumeWindow = Duration(minutes: 30);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String get _uid {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError('No existe un usuario autenticado.');
    }

    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _chats {
    return _firestore.collection('usuarios').doc(_uid).collection('chats');
  }

  CollectionReference<Map<String, dynamic>> _messages(String chatId) {
    return _chats.doc(chatId).collection('mensajes');
  }

  void _requireServerSnapshot(SnapshotMetadata metadata) {
    if (metadata.isFromCache || metadata.hasPendingWrites) {
      throw const AiChatUnconfirmedDataException();
    }
  }

  // =========================================================
  // CHAT ACTIVO / REANUDACIÓN DE 30 MIN
  // =========================================================

  @override
  Future<AiConversation?> getConversationToResume() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _chats.get(
      const GetOptions(source: Source.server),
    );
    _requireServerSnapshot(snapshot.metadata);

    final List<AiConversation> active = snapshot.docs
        .map((doc) => AiConversation.fromMap(id: doc.id, data: doc.data()))
        .where((conversation) => !conversation.archived)
        .toList();

    if (active.isEmpty) {
      return null;
    }

    active.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final AiConversation newest = active.first;

    // Si por alguna razón quedaron dos chats activos,
    // dejamos solamente el más reciente.
    for (int index = 1; index < active.length; index++) {
      await archiveConversation(active[index].id);
    }

    final DateTime reference = newest.lastExitAt ?? newest.lastMessageAt;

    final Duration elapsed = DateTime.now().difference(reference);

    if (elapsed >= resumeWindow) {
      await archiveConversation(newest.id);
      return null;
    }

    await markEntered(newest.id);

    return newest.copyWith(clearLastExitAt: true, archived: false);
  }

  // =========================================================
  // CREAR
  // =========================================================

  @override
  Future<AiConversation> createConversation(
    String firstMessage, {
    String? conversationId,
  }) async {
    final DocumentReference<Map<String, dynamic>> ref = _chats.doc(
      conversationId,
    );

    final DateTime now = DateTime.now();

    final AiConversation conversation = AiConversation(
      id: ref.id,
      title: _buildTitle(firstMessage),
      createdAt: now,
      updatedAt: now,
      lastMessageAt: now,
      lastExitAt: null,
      messageCount: 0,
      archived: false,
    );

    final data = <String, dynamic>{
      'titulo': conversation.title,
      'creadoEn': Timestamp.fromDate(now),
      'actualizadoEn': Timestamp.fromDate(now),
      'ultimoMensajeEn': Timestamp.fromDate(now),
      'cantidadMensajes': 0,
      'archivado': false,
      'ultimaSalidaEn': null,
    };
    final snapshot = await _chats.get(const GetOptions(source: Source.server));
    _requireServerSnapshot(snapshot.metadata);
    final otherActive = snapshot.docs
        .where((doc) {
          if (doc.id == ref.id) return false;
          return doc.data()['archivado'] != true;
        })
        .toList(growable: false);

    // Las transacciones fallan sin conexión y no dejan una escritura local en
    // cola. El ID estable permite reintentar si se agotó el plazo de espera.
    return _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      final active = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in otherActive) {
        active.add(await transaction.get(doc.reference));
      }
      if (existing.exists) {
        return AiConversation.fromMap(id: ref.id, data: existing.data()!);
      }
      for (final doc in active) {
        if (doc.exists && doc.data()?['archivado'] != true) {
          transaction.set(doc.reference, {
            'archivado': true,
            'ultimaSalidaEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
      transaction.set(ref, data);
      return conversation;
    });
  }

  // =========================================================
  // MENSAJES
  // =========================================================

  @override
  Future<AiChatMessage> addMessage({
    required String chatId,
    required AiChatRole role,
    required String text,
    bool isError = false,
    String? messageId,
    String? clearErrorMessageId,
  }) async {
    final String clean = text.trim();

    if (clean.isEmpty) {
      throw ArgumentError('El mensaje no puede estar vacío.');
    }

    final DocumentReference<Map<String, dynamic>> messageRef = _messages(chatId)
        .doc(messageId);

    final DateTime now = DateTime.now();

    final AiChatMessage message = AiChatMessage(
      id: messageRef.id,
      role: role,
      text: clean,
      createdAt: now,
      isError: isError,
    );

    final chatRef = _chats.doc(chatId);
    return _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(messageRef);
      final chat = await transaction.get(chatRef);
      final errorRef = clearErrorMessageId == null
          ? null
          : _messages(chatId).doc(clearErrorMessageId);
      final previousError = errorRef == null
          ? null
          : await transaction.get(errorRef);
      final shouldClearError =
          previousError?.exists == true &&
          previousError?.data()?['esError'] == true;
      if (existing.exists) {
        if (isError && existing.data()?['esError'] == true) {
          if (!chat.exists || chat.data()?['archivado'] == true) {
            throw StateError('La conversación ya no está activa.');
          }
          transaction.set(messageRef, message.toMap());
          transaction.set(chatRef, {
            'actualizadoEn': Timestamp.fromDate(now),
            'ultimoMensajeEn': Timestamp.fromDate(now),
          }, SetOptions(merge: true));
          return message;
        }
        if (shouldClearError) {
          transaction.delete(errorRef!);
          transaction.set(chatRef, {
            'cantidadMensajes': FieldValue.increment(-1),
          }, SetOptions(merge: true));
        }
        return AiChatMessage.fromMap(id: messageRef.id, data: existing.data()!);
      }
      if (!chat.exists || chat.data()?['archivado'] == true) {
        throw StateError('La conversación ya no está activa.');
      }
      transaction.set(messageRef, message.toMap());
      if (shouldClearError) transaction.delete(errorRef!);
      transaction.set(chatRef, {
        'actualizadoEn': Timestamp.fromDate(now),
        'ultimoMensajeEn': Timestamp.fromDate(now),
        'ultimaSalidaEn': null,
        'archivado': false,
        'cantidadMensajes': FieldValue.increment(shouldClearError ? 0 : 1),
      }, SetOptions(merge: true));
      return message;
    });
  }

  @override
  Future<List<AiChatMessage>> getMessages(String chatId) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _messages(chatId)
        .orderBy('creadoEn')
        .get(const GetOptions(source: Source.server));
    _requireServerSnapshot(snapshot.metadata);

    return snapshot.docs
        .map((doc) => AiChatMessage.fromMap(id: doc.id, data: doc.data()))
        .toList();
  }

  // =========================================================
  // LISTADO
  // =========================================================

  @override
  Future<List<AiConversation>> getConversations() async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _chats.get(
      const GetOptions(source: Source.server),
    );
    _requireServerSnapshot(snapshot.metadata);

    final List<AiConversation> conversations = snapshot.docs
        .map((doc) => AiConversation.fromMap(id: doc.id, data: doc.data()))
        .toList();

    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return conversations;
  }

  // =========================================================
  // ESTADO
  // =========================================================

  @override
  Future<void> markExited(String chatId) async {
    await _setChatOnline(chatId, {
      'ultimaSalidaEn': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> markEntered(String chatId) async {
    await _setChatOnline(chatId, {
      'ultimaSalidaEn': FieldValue.delete(),
      'archivado': false,
    });
  }

  @override
  Future<void> archiveConversation(String chatId) async {
    await _setChatOnline(chatId, {
      'archivado': true,
      'ultimaSalidaEn': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<AiConversation> reactivateConversation(
    AiConversation conversation,
  ) async {
    await _archiveOtherActiveChats(exceptId: conversation.id);

    await _setChatOnline(conversation.id, {
      'archivado': false,
      'ultimaSalidaEn': FieldValue.delete(),
    });

    return conversation.copyWith(archived: false, clearLastExitAt: true);
  }

  // =========================================================
  // ELIMINAR
  // =========================================================

  @override
  Future<void> deleteConversation(String chatId) async {
    while (true) {
      final QuerySnapshot<Map<String, dynamic>> snapshot = await _messages(
        chatId,
      ).limit(400).get();

      if (snapshot.docs.isEmpty) {
        break;
      }

      final WriteBatch batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (snapshot.docs.length < 400) {
        break;
      }
    }

    await _chats.doc(chatId).delete();
  }

  // =========================================================
  // HELPERS
  // =========================================================

  Future<void> _archiveOtherActiveChats({required String exceptId}) async {
    final QuerySnapshot<Map<String, dynamic>> snapshot = await _chats.get(
      const GetOptions(source: Source.server),
    );
    _requireServerSnapshot(snapshot.metadata);
    final active = snapshot.docs
        .where((doc) => doc.id != exceptId && doc.data()['archivado'] != true)
        .toList(growable: false);
    if (active.isEmpty) return;
    await _firestore.runTransaction((transaction) async {
      final confirmed = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final doc in active) {
        confirmed.add(await transaction.get(doc.reference));
      }
      for (final doc in confirmed) {
        if (doc.exists && doc.data()?['archivado'] != true) {
          transaction.set(doc.reference, {
            'archivado': true,
            'ultimaSalidaEn': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    });
  }

  Future<void> _setChatOnline(String chatId, Map<String, dynamic> data) async {
    final ref = _chats.doc(chatId);
    await _firestore.runTransaction((transaction) async {
      final chat = await transaction.get(ref);
      if (!chat.exists) throw StateError('La conversación no existe.');
      transaction.set(ref, data, SetOptions(merge: true));
    });
  }

  String _buildTitle(String firstMessage) {
    String clean = firstMessage.replaceAll(RegExp(r'\s+'), ' ').trim();

    clean = clean
        .replaceFirst(RegExp(r'''^[¿¡"']+'''), '')
        .replaceFirst(RegExp(r'''[?!"']+$'''), '')
        .trim();

    if (clean.isEmpty) {
      return 'Nuevo chat';
    }

    if (clean.length > 54) {
      clean = '${clean.substring(0, 51).trimRight()}...';
    }

    return clean[0].toUpperCase() + clean.substring(1);
  }
}
