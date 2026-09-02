import 'package:firebase_auth/firebase_auth.dart';

enum AiChatMessageRole { user, assistant }

class AiChatStoredMessage {
  const AiChatStoredMessage({
    required this.role,
    required this.text,
    this.isError = false,
  });

  final AiChatMessageRole role;
  final String text;
  final bool isError;

  bool get isUser => role == AiChatMessageRole.user;
}

class AiChatSessionStore {
  AiChatSessionStore._();

  static final AiChatSessionStore instance = AiChatSessionStore._();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Map<String, List<AiChatStoredMessage>> _messagesByUid = {};

  String? get _uid => _auth.currentUser?.uid;

  List<AiChatStoredMessage> get currentMessages {
    final String? uid = _uid;

    if (uid == null) {
      return const [];
    }

    return List<AiChatStoredMessage>.unmodifiable(
      _messagesByUid[uid] ?? const [],
    );
  }

  void addUserMessage(String text) {
    _add(AiChatStoredMessage(role: AiChatMessageRole.user, text: text));
  }

  void addAssistantMessage(String text, {bool isError = false}) {
    _add(
      AiChatStoredMessage(
        role: AiChatMessageRole.assistant,
        text: text,
        isError: isError,
      ),
    );
  }

  void clearCurrentConversation() {
    final String? uid = _uid;

    if (uid == null) {
      return;
    }

    _messagesByUid.remove(uid);
  }

  void clearUser(String uid) {
    _messagesByUid.remove(uid);
  }

  void clearAll() {
    _messagesByUid.clear();
  }

  void _add(AiChatStoredMessage message) {
    final String? uid = _uid;

    if (uid == null) {
      return;
    }

    final List<AiChatStoredMessage> messages = _messagesByUid.putIfAbsent(
      uid,
      () => <AiChatStoredMessage>[],
    );

    messages.add(message);
  }
}
