import 'package:cloud_firestore/cloud_firestore.dart';

enum AiChatRole { user, assistant }

AiChatRole aiChatRoleFromFirestore(dynamic value) {
  return value?.toString() == 'assistant'
      ? AiChatRole.assistant
      : AiChatRole.user;
}

extension AiChatRoleFirestore on AiChatRole {
  String get firestoreValue {
    switch (this) {
      case AiChatRole.user:
        return 'user';
      case AiChatRole.assistant:
        return 'assistant';
    }
  }
}

DateTime _dateTimeFromFirestore(
  dynamic value, {
  DateTime? fallback,
}) {
  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    return DateTime.tryParse(value) ??
        fallback ??
        DateTime.now();
  }

  return fallback ?? DateTime.now();
}

DateTime? _dateTimeNullableFromFirestore(
  dynamic value,
) {
  if (value == null) {
    return null;
  }

  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    return DateTime.tryParse(value);
  }

  return null;
}

class AiConversation {
  const AiConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.lastMessageAt,
    required this.messageCount,
    required this.archived,
    this.lastExitAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime lastMessageAt;
  final DateTime? lastExitAt;
  final int messageCount;
  final bool archived;

  AiConversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastMessageAt,
    DateTime? lastExitAt,
    bool clearLastExitAt = false,
    int? messageCount,
    bool? archived,
  }) {
    return AiConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessageAt:
          lastMessageAt ?? this.lastMessageAt,
      lastExitAt: clearLastExitAt
          ? null
          : lastExitAt ?? this.lastExitAt,
      messageCount:
          messageCount ?? this.messageCount,
      archived: archived ?? this.archived,
    );
  }

  factory AiConversation.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    final DateTime fallback = DateTime.now();

    final String rawTitle =
        data['titulo']?.toString().trim() ?? '';

    final DateTime createdAt =
        _dateTimeFromFirestore(
      data['creadoEn'],
      fallback: fallback,
    );

    final DateTime updatedAt =
        _dateTimeFromFirestore(
      data['actualizadoEn'],
      fallback: createdAt,
    );

    final DateTime lastMessageAt =
        _dateTimeFromFirestore(
      data['ultimoMensajeEn'],
      fallback: updatedAt,
    );

    return AiConversation(
      id: id,
      title:
          rawTitle.isNotEmpty ? rawTitle : 'Chat',
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastMessageAt: lastMessageAt,
      lastExitAt:
          _dateTimeNullableFromFirestore(
        data['ultimaSalidaEn'],
      ),
      messageCount:
          (data['cantidadMensajes'] as num?)
                  ?.toInt() ??
              0,
      archived: data['archivado'] is bool
          ? data['archivado'] as bool
          : false,
    );
  }
}

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.isError = false,
  });

  final String id;
  final AiChatRole role;
  final String text;
  final DateTime createdAt;
  final bool isError;

  bool get isUser => role == AiChatRole.user;

  factory AiChatMessage.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return AiChatMessage(
      id: id,
      role:
          aiChatRoleFromFirestore(data['rol']),
      text: data['texto']?.toString() ?? '',
      createdAt: _dateTimeFromFirestore(
        data['creadoEn'],
      ),
      isError: data['esError'] is bool
          ? data['esError'] as bool
          : false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'rol': role.firestoreValue,
      'texto': text,
      'creadoEn': Timestamp.fromDate(createdAt),
      'esError': isError,
    };
  }
}
