import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/ai_conversation.dart';

class AiChatHistoryService {
  AiChatHistoryService._();

  static final AiChatHistoryService instance =
      AiChatHistoryService._();

  static const Duration resumeWindow =
      Duration(minutes: 30);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  String get _uid {
    final User? user = _auth.currentUser;

    if (user == null) {
      throw StateError(
        'No existe un usuario autenticado.',
      );
    }

    return user.uid;
  }

  CollectionReference<Map<String, dynamic>>
  get _chats {
    return _firestore
        .collection('usuarios')
        .doc(_uid)
        .collection('chats');
  }

  CollectionReference<Map<String, dynamic>>
  _messages(String chatId) {
    return _chats
        .doc(chatId)
        .collection('mensajes');
  }

  // =========================================================
  // CHAT ACTIVO / REANUDACIÓN DE 30 MIN
  // =========================================================

  Future<AiConversation?>
  getConversationToResume() async {
    final QuerySnapshot<Map<String, dynamic>>
    snapshot = await _chats.get();

    final List<AiConversation> active =
        snapshot.docs
            .map(
              (doc) => AiConversation.fromMap(
                id: doc.id,
                data: doc.data(),
              ),
            )
            .where(
              (conversation) =>
                  !conversation.archived,
            )
            .toList();

    if (active.isEmpty) {
      return null;
    }

    active.sort(
      (a, b) => b.updatedAt.compareTo(
        a.updatedAt,
      ),
    );

    final AiConversation newest = active.first;

    // Si por alguna razón quedaron dos chats activos,
    // dejamos solamente el más reciente.
    for (
      int index = 1;
      index < active.length;
      index++
    ) {
      await archiveConversation(
        active[index].id,
      );
    }

    final DateTime reference =
        newest.lastExitAt ??
        newest.lastMessageAt;

    final Duration elapsed =
        DateTime.now().difference(reference);

    if (elapsed >= resumeWindow) {
      await archiveConversation(newest.id);
      return null;
    }

    await markEntered(newest.id);

    return newest.copyWith(
      clearLastExitAt: true,
      archived: false,
    );
  }

  // =========================================================
  // CREAR
  // =========================================================

  Future<AiConversation> createConversation(
    String firstMessage,
  ) async {
    final DocumentReference<Map<String, dynamic>>
    ref = _chats.doc();

    final DateTime now = DateTime.now();

    final AiConversation conversation =
        AiConversation(
      id: ref.id,
      title: _buildTitle(firstMessage),
      createdAt: now,
      updatedAt: now,
      lastMessageAt: now,
      lastExitAt: null,
      messageCount: 0,
      archived: false,
    );

    // Solo debe existir una conversación activa.
    await _archiveOtherActiveChats(
      exceptId: conversation.id,
    );

    await ref.set({
      'titulo': conversation.title,
      'creadoEn': Timestamp.fromDate(now),
      'actualizadoEn':
          Timestamp.fromDate(now),
      'ultimoMensajeEn':
          Timestamp.fromDate(now),
      'cantidadMensajes': 0,
      'archivado': false,
      'ultimaSalidaEn': null,
    });

    return conversation;
  }

  // =========================================================
  // MENSAJES
  // =========================================================

  Future<AiChatMessage> addMessage({
    required String chatId,
    required AiChatRole role,
    required String text,
    bool isError = false,
  }) async {
    final String clean = text.trim();

    if (clean.isEmpty) {
      throw ArgumentError(
        'El mensaje no puede estar vacío.',
      );
    }

    final DocumentReference<Map<String, dynamic>>
    messageRef = _messages(chatId).doc();

    final DateTime now = DateTime.now();

    final AiChatMessage message =
        AiChatMessage(
      id: messageRef.id,
      role: role,
      text: clean,
      createdAt: now,
      isError: isError,
    );

    final WriteBatch batch =
        _firestore.batch();

    batch.set(
      messageRef,
      message.toMap(),
    );

    batch.set(
      _chats.doc(chatId),
      {
        'actualizadoEn':
            Timestamp.fromDate(now),
        'ultimoMensajeEn':
            Timestamp.fromDate(now),
        'ultimaSalidaEn': null,
        'archivado': false,
        'cantidadMensajes':
            FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    return message;
  }

  Future<List<AiChatMessage>> getMessages(
    String chatId,
  ) async {
    final QuerySnapshot<Map<String, dynamic>>
    snapshot = await _messages(chatId)
        .orderBy('creadoEn')
        .get();

    return snapshot.docs
        .map(
          (doc) => AiChatMessage.fromMap(
            id: doc.id,
            data: doc.data(),
          ),
        )
        .toList();
  }

  // =========================================================
  // LISTADO
  // =========================================================

  Future<List<AiConversation>>
  getConversations() async {
    final QuerySnapshot<Map<String, dynamic>>
    snapshot = await _chats.get();

    final List<AiConversation> conversations =
        snapshot.docs
            .map(
              (doc) => AiConversation.fromMap(
                id: doc.id,
                data: doc.data(),
              ),
            )
            .toList();

    conversations.sort(
      (a, b) => b.updatedAt.compareTo(
        a.updatedAt,
      ),
    );

    return conversations;
  }

  // =========================================================
  // ESTADO
  // =========================================================

  Future<void> markExited(
    String chatId,
  ) async {
    await _chats.doc(chatId).set(
      {
        'ultimaSalidaEn':
            FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> markEntered(
    String chatId,
  ) async {
    await _chats.doc(chatId).set(
      {
        'ultimaSalidaEn':
            FieldValue.delete(),
        'archivado': false,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> archiveConversation(
    String chatId,
  ) async {
    await _chats.doc(chatId).set(
      {
        'archivado': true,
        'ultimaSalidaEn':
            FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<AiConversation>
  reactivateConversation(
    AiConversation conversation,
  ) async {
    await _archiveOtherActiveChats(
      exceptId: conversation.id,
    );

    await _chats.doc(conversation.id).set(
      {
        'archivado': false,
        'ultimaSalidaEn':
            FieldValue.delete(),
      },
      SetOptions(merge: true),
    );

    return conversation.copyWith(
      archived: false,
      clearLastExitAt: true,
    );
  }

  // =========================================================
  // ELIMINAR
  // =========================================================

  Future<void> deleteConversation(
    String chatId,
  ) async {
    while (true) {
      final QuerySnapshot<Map<String, dynamic>>
      snapshot = await _messages(chatId)
          .limit(400)
          .get();

      if (snapshot.docs.isEmpty) {
        break;
      }

      final WriteBatch batch =
          _firestore.batch();

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

  Future<void> _archiveOtherActiveChats({
    required String exceptId,
  }) async {
    final QuerySnapshot<Map<String, dynamic>>
    snapshot = await _chats.get();

    final WriteBatch batch =
        _firestore.batch();

    bool hasWrites = false;

    for (final doc in snapshot.docs) {
      if (doc.id == exceptId) {
        continue;
      }

      final Map<String, dynamic> data =
          doc.data();

      final bool archived =
          data['archivado'] is bool
          ? data['archivado'] as bool
          : false;

      if (archived) {
        continue;
      }

      batch.set(
        doc.reference,
        {
          'archivado': true,
          'ultimaSalidaEn':
              FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      hasWrites = true;
    }

    if (hasWrites) {
      await batch.commit();
    }
  }

  String _buildTitle(String firstMessage) {
    String clean = firstMessage
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    clean = clean
        .replaceFirst(
          RegExp(r'''^[¿¡"']+'''),
          '',
        )
        .replaceFirst(
          RegExp(r'''[?!"']+$'''),
          '',
        )
        .trim();

    if (clean.isEmpty) {
      return 'Nuevo chat';
    }

    if (clean.length > 54) {
      clean =
          '${clean.substring(0, 51).trimRight()}...';
    }

    return clean[0].toUpperCase() +
        clean.substring(1);
  }
}
