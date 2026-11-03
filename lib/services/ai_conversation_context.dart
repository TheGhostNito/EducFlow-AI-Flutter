import '../models/ai_conversation.dart';

/// Conserva únicamente intercambios completos de la conversación activa.
/// El mensaje que se está enviando no se repite dentro del historial.
class AiConversationContext {
  const AiConversationContext._();

  static List<AiChatMessage> completedHistory(
    List<AiChatMessage> messages, {
    required String currentMessage,
    int maxMessages = 24,
  }) {
    final valid = messages
        .where((message) => !message.isError && message.text.trim().isNotEmpty)
        .toList();
    if (valid.isNotEmpty &&
        valid.last.role == AiChatRole.user &&
        valid.last.text.trim() == currentMessage.trim()) {
      valid.removeLast();
    }

    final completed = <AiChatMessage>[];
    AiChatMessage? pendingUser;
    for (final message in valid) {
      if (message.role == AiChatRole.user) {
        pendingUser = message;
      } else if (pendingUser != null) {
        completed.add(pendingUser);
        completed.add(message);
        pendingUser = null;
      }
    }
    final maxPairs = maxMessages ~/ 2;
    if (completed.length > maxPairs * 2) {
      return completed.sublist(completed.length - maxPairs * 2);
    }
    return completed;
  }
}
